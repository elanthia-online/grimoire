require 'fileutils'
require 'rbconfig'
require_relative 'launched_lich'
require_relative 'session_logger'

module Grimoire
  # Starts a headless Lich for a saved character (a LichInstall::Entry):
  #
  #   <ruby> <lich_dir>/lich.rbw --login NAME --headless auto <game flags>
  #
  # lich-5's preferred headless launch form. --headless auto is its own
  # shorthand for --without-frontend with an OS-assigned detachable-client
  # port (lib/main/arg_normalization.rb), so grimoire never picks a port:
  # Lich writes the one it bound into <Name>.session, which is how the
  # session is found and attached afterwards, the same way a dropped
  # session is found again (Shell's rescan). Lich still does the whole
  # login from its saved entry; grimoire only starts the process
  # (CLAUDE.md's "Connection model").
  #
  # The game is chosen with lich-5's game selection flags, not
  # --game-code, which is for creating saved entries (--add-character),
  # not for picking one to log in with.
  #
  # Runs lich.rbw with the Ruby grimoire itself is running on
  # (RbConfig.ruby). lich-5's .ruby-version is a development pin that is
  # not part of a user's Lich install, so there is nothing else to honor.
  #
  # Nothing here touches GTK, and nothing blocks beyond spawning the
  # process: waiting for the session file and attaching is the caller's
  # job (TASKS.md's "Headless launch" item 5).
  class LichLauncher
    Error = Class.new(StandardError)

    # lich-5's game selection flags per game code (LoginHelpers
    # .resolve_instance), limited to the codes it accepts for login
    # (LoginHelpers::VALID_GAME_CODES). The game prefix is always passed:
    # --test and --platinum alone do not say which game.
    GAME_FLAGS = {
      'GS3' => %w[--gemstone],
      'GST' => %w[--gemstone --test],
      'GSF' => %w[--gemstone --shattered],
      'DR'  => %w[--dragonrealms],
      'DRX' => %w[--dragonrealms --platinum],
      'DRT' => %w[--dragonrealms --test],
      'DRF' => %w[--dragonrealms --fallen],
    }.freeze

    # Game codes an older entry.yaml can still hold for an instance that
    # has since shut down, so an old favorite gets a clear reason rather
    # than a Lich that fails to log in.
    CLOSED_GAMES = {
      'GSX' => 'GemStone IV Platinum',
    }.freeze

    # A child in its own process group, so a Ctrl-C in the terminal grimoire
    # was started from interrupts grimoire only, not every Lich it launched.
    PROCESS_GROUP = Gem.win_platform? ? { new_pgroup: true } : { pgroup: true }

    attr_reader :launched

    # clock: is for specs; ruby: is which interpreter runs lich.rbw.
    def initialize(install:, log_dir:, ruby: RbConfig.ruby, clock: Time)
      @install  = install
      @log_dir  = log_dir
      @ruby     = ruby
      @clock    = clock
      @launched = []
    end

    # Starts Lich for entry and returns its LaunchedLich. on_exit is called
    # with that LaunchedLich when the process ends, on a background thread.
    # Raises Error, before starting anything, when the install is unusable
    # or the entry's game cannot be launched.
    def launch(entry, on_exit: nil)
      problem = @install.problem
      raise Error, problem if problem

      args       = command(entry)
      log_path   = log_path_for(entry)
      started_at = @clock.now
      pid        = spawn(args, log_path)

      LaunchedLich.new(entry: entry, pid: pid, log_path: log_path, started_at: started_at, on_exit: on_exit).tap do |process|
        @launched << process
      end
    end

    def command(entry)
      [@ruby, @install.lich_rbw_path, '--login', entry.char_name, '--headless', 'auto', *game_flags(entry)]
    end

    private

    def game_flags(entry)
      code = entry.game_code.to_s.upcase
      GAME_FLAGS.fetch(code) do
        closed = CLOSED_GAMES[code]
        raise Error, "#{entry.char_name}: #{closed} (#{code}) has closed" if closed

        raise Error, "#{entry.char_name}: Lich cannot log in to game code #{entry.game_code.inspect}"
      end
    end

    # Named like SessionLogger's files, and sanitized the same way, since
    # char_name comes from a file grimoire does not control. Always
    # written, not only under --autolog: it is where a failed login's
    # reason ends up.
    def log_path_for(entry)
      FileUtils.mkdir_p(@log_dir)
      label = entry.char_name.to_s.gsub(SessionLogger::UNSAFE_LABEL_CHARACTERS, '').downcase.capitalize
      name  = ['lich', label, @clock.now.strftime('%Y%m%d-%H%M%S')].reject(&:empty?).join('-')
      File.join(@log_dir, "#{name}.log")
    end

    # stdin is closed off so a Lich that unexpectedly prompts fails instead
    # of hanging with no terminal to answer it. The environment drops
    # Bundler's variables: grimoire usually runs under `bundle exec`, and
    # a child inheriting BUNDLE_GEMFILE/RUBYOPT would load grimoire's gem
    # bundle instead of Lich's own gems.
    def spawn(args, log_path)
      File.open(log_path, 'a') do |log|
        Process.spawn(child_env, *args, unsetenv_others: true, chdir: @install.dir,
                      in: File::NULL, out: log, err: log, **PROCESS_GROUP)
      end
    rescue SystemCallError => e
      raise Error, "could not start #{args.first} #{args[1]}: #{e.message}"
    end

    def child_env
      defined?(Bundler) ? Bundler.unbundled_env : ENV.to_h
    end
  end
end
