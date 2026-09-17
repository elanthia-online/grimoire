module Grimoire
  # One Lich process LichLauncher started: which saved character it is
  # logging in, where its output goes, and whether it is still running.
  # The port it listens on is not known here -- Lich picks it (--headless
  # auto) and writes it to the character's session file.
  #
  # Exit is detected by a waiter thread blocked in Process.wait2, which
  # also reaps the child so it never lingers as a zombie. on_exit fires on
  # that thread, not the GTK main thread -- a caller that touches widgets
  # from it must marshal through GLib::Idle.add, the same rule Session
  # follows for Connection's read thread.
  class LaunchedLich
    # started_at is wall-clock time taken just before spawning, which
    # LaunchWatcher compares session file modification times against.
    attr_reader :entry, :pid, :log_path, :started_at

    def initialize(entry:, pid:, log_path:, started_at:, on_exit: nil)
      @entry       = entry
      @started_at  = started_at
      @pid         = pid
      @log_path    = log_path
      @on_exit     = on_exit
      @exit_status = nil
      @mutex       = Mutex.new
      @waiter      = Thread.new { wait_for_exit }
    end

    def character
      @entry.char_name
    end

    # Process::Status once the process has exited, nil while it runs.
    def exit_status
      @mutex.synchronize { @exit_status }
    end

    def running?
      exit_status.nil?
    end

    # Blocks until the process exits or timeout seconds pass (nil waits
    # forever). Returns the exit status, or nil if it is still running.
    def wait(timeout = nil)
      @waiter.join(timeout)
      exit_status
    end

    # Asks the process to end: TERM, so Lich gets a chance to shut down
    # cleanly. Windows has no TERM, so it gets KILL there. Only a request;
    # #wait or on_exit reports when it has actually gone. Does nothing once
    # the process has exited -- the waiter has reaped it by then, so its
    # pid could already belong to an unrelated process.
    #
    # This ends the Lich process, not the game character's login the way
    # sending `quit` would; BACKLOG.md's per-character close behavior covers that.
    def stop
      return false unless running?

      Process.kill(Gem.win_platform? ? 'KILL' : 'TERM', @pid)
      true
    rescue Errno::ESRCH
      false
    end

    # The last lines Lich wrote (stdout and stderr share the log), for
    # showing why a launch failed.
    def output_tail(lines = 20)
      File.readlines(@log_path).last(lines).join
    rescue SystemCallError
      ''
    end

    private

    def wait_for_exit
      _, status = Process.wait2(@pid)
      @mutex.synchronize { @exit_status = status }
      @on_exit&.call(self)
    end
  end
end
