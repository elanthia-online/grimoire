require 'json'
require 'tmpdir'

module Grimoire
  # Locates the host/port lich-5 opened for a character, by reading the
  # session descriptor file Lich::Common::Frontend.create_session_file
  # writes on the --detachable-client accept path (lich-5's own
  # lib/common/frontend.rb) -- only when lich-5 was started with both
  # --login <name> and --detachable-client. Mirrors lich-5's own path/name
  # rule rather than hardcoding /tmp, since Dir.tmpdir already resolves
  # per-platform (and per TMPDIR/TEMP/TMP) the same way lich-5's does.
  class SessionLocator
    # File does not exist (after retries) -- lich-5 is not running with
    # --login/--detachable-client for this character, or has not gotten
    # far enough to write the file yet.
    NotFound = Class.new(StandardError)

    # File exists but is not usable -- malformed JSON, or missing/invalid
    # host or port. Distinct from NotFound so the caller can tell "lich-5
    # is not up for this character" apart from "something wrote a bad
    # file", which point at different fixes.
    InvalidSession = Class.new(StandardError)

    SESSION_DIR = File.join(Dir.tmpdir, 'simutronics', 'sessions')

    # One entry per *.session file found by .list. character comes from the
    # filename (already lich-5's own downcase.capitalize'd name), not the
    # JSON body's "name" field, so it is available even for a malformed
    # file that .list still wants to report on. error is nil for a usable
    # entry; when set, host/port are nil and error explains why.
    Session = Struct.new(:character, :host, :port, :error, keyword_init: true) do
      def valid?
        error.nil?
      end
    end

    # ~3s total (6 * 0.5s), enough to absorb the ordinary startup race
    # where grimoire is launched a beat before lich-5 finishes binding its
    # detachable-client listener and calling create_session_file. Does not
    # cover a stale-but-well-formed file left over from a reconnect --
    # that can only be caught by attempting the TCP connect itself, so
    # it is handled as a separate retry loop in the grimoire executable.
    DEFAULT_RETRIES = 6
    DEFAULT_RETRY_INTERVAL = 0.5

    def self.session_file_path(character_name, session_dir: SESSION_DIR)
      File.join(session_dir, "#{character_name.to_s.downcase.capitalize}.session")
    end

    # Every *.session file currently in session_dir, valid or not -- a
    # malformed file is still reported (as a Session with error set)
    # rather than silently skipped, since --list's whole point is telling
    # the user what is actually sitting in that directory right now.
    def self.list(session_dir: SESSION_DIR)
      Dir.glob(File.join(session_dir, '*.session')).sort.map do |path|
        character = File.basename(path, '.session')
        data = JSON.parse(File.read(path))

        if data.is_a?(Hash) && data['host'].is_a?(String) && data['port'].is_a?(Integer)
          Session.new(character: character, host: data['host'], port: data['port'], error: nil)
        else
          Session.new(character: character, host: nil, port: nil, error: 'missing or invalid host/port field')
        end
      rescue JSON::ParserError => e
        Session.new(character: character, host: nil, port: nil, error: "malformed session file (#{e.message})")
      end
    end

    def initialize(character_name, session_dir: SESSION_DIR, retries: DEFAULT_RETRIES,
                   retry_interval: DEFAULT_RETRY_INTERVAL)
      @character_name = character_name
      @path           = self.class.session_file_path(character_name, session_dir: session_dir)
      @retries        = retries
      @retry_interval = retry_interval
    end

    # Returns { host:, port: }. Raises NotFound or InvalidSession once
    # retries are exhausted.
    def locate
      attempts = 0
      begin
        attempts += 1
        read_and_validate
      rescue NotFound, InvalidSession
        raise if attempts > @retries

        sleep @retry_interval
        retry
      end
    end

    private

    def read_and_validate
      raise NotFound, not_found_message unless File.file?(@path)

      data = JSON.parse(File.read(@path))
      validate!(data)
      { host: data['host'], port: data['port'] }
    rescue JSON::ParserError => e
      raise InvalidSession, "#{@path}: malformed session file (#{e.message})"
    end

    # The file's own "name" field is not cross-checked here -- it is
    # informational only, since grimoire already derived @path from the
    # same character name it is looking up.
    def validate!(data)
      missing = %w[host port].reject { |field| data.key?(field) }
      raise InvalidSession, "#{@path}: missing field(s) #{missing.join(', ')}" unless missing.empty?
      raise InvalidSession, "#{@path}: host must be a non-empty string" unless valid_host?(data['host'])
      raise InvalidSession, "#{@path}: port must be an integer 1..65535" unless valid_port?(data['port'])
    end

    def valid_host?(host)
      host.is_a?(String) && !host.empty?
    end

    def valid_port?(port)
      port.is_a?(Integer) && (1..65_535).cover?(port)
    end

    def not_found_message
      "no session file for '#{@character_name}' at #{@path} " \
        "(is lich-5 running with --login #{@character_name} --detachable-client?)"
    end
  end
end
