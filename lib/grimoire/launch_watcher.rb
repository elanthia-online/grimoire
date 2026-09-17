require_relative 'session_locator'

module Grimoire
  # Watches one LaunchedLich until its session can be attached: a single
  # non-blocking #check per call, so the shell can drive it from a
  # GLib::Timeout without freezing the UI (SessionLocator#locate's retry
  # loop sleeps, which is only safe before the GTK main loop starts).
  #
  # Ready means the character's session file exists, is valid, and was
  # written by *this* launch. lich-5 writes <Name>.session as soon as its
  # detachable-client listener binds, before any frontend connects
  # (lib/main/main.rb), and with --headless auto that file is the only
  # place the OS-assigned port appears. A file left behind by an earlier
  # Lich that crashed names a port nobody is listening on, so a file older
  # than the launch is ignored.
  class LaunchWatcher
    # One #check outcome. state is :waiting, :ready (host/port set),
    # :exited or :timed_out (detail set, for showing the user).
    Result = Struct.new(:state, :host, :port, :detail, keyword_init: true)

    WAITING = Result.new(state: :waiting).freeze

    # Lich logs in before it binds the listener, so this covers the whole
    # login, not only process startup.
    DEFAULT_TIMEOUT = 120

    # Allowance for filesystems that store modification times coarsely
    # (FAT keeps 2-second steps). A stale file inside this window still
    # fails to connect, and the caller keeps checking until Lich rewrites
    # it or the timeout passes.
    MTIME_SLACK = 2

    attr_reader :launched

    # clock returns monotonic seconds, like Shell's, so the timeout cannot
    # be stretched or cut short by a wall-clock change. launched.started_at
    # is wall-clock time, since that is what a file's mtime is compared to.
    def initialize(launched, session_dir: SessionLocator::SESSION_DIR, timeout: DEFAULT_TIMEOUT,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @launched    = launched
      @session_dir = session_dir
      @timeout     = timeout
      @clock       = clock
      @deadline    = clock.call + timeout
    end

    # Exit is checked first: a crashed Lich can leave a fresh but useless
    # session file behind. The timeout comes before readiness so a session
    # file that never accepts a connection cannot keep the caller retrying
    # forever.
    def check
      return exited unless @launched.running?
      return timed_out if @clock.call >= @deadline

      session = fresh_session
      session ? Result.new(state: :ready, host: session[:host], port: session[:port]) : WAITING
    end

    private

    def fresh_session
      path = SessionLocator.session_file_path(@launched.character, session_dir: @session_dir)
      return nil unless File.file?(path) && File.mtime(path) >= @launched.started_at - MTIME_SLACK

      SessionLocator.new(@launched.character, session_dir: @session_dir, retries: 0).locate
    rescue SessionLocator::NotFound, SessionLocator::InvalidSession, SystemCallError
      # Deleted between the checks, or caught mid-write. Try again next time.
      nil
    end

    def exited
      status = @launched.exit_status
      how    = status.exitstatus ? "with status #{status.exitstatus}" : "on signal #{status.termsig}"
      Result.new(state: :exited, detail: with_output("Lich exited #{how} before its session was ready."))
    end

    def timed_out
      Result.new(
        state: :timed_out,
        detail: with_output("No session file after #{@timeout} seconds. Lich is still running and can be attached later.")
      )
    end

    def with_output(message)
      output = @launched.output_tail
      output.empty? ? message : "#{message}\n\nLast output (#{@launched.log_path}):\n#{output}"
    end
  end
end
