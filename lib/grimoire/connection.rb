require 'socket'

module Grimoire
  # TCP client for Lich's detachable-client (frontend) socket. Lich owns
  # login, session, and EAS; this class only connects to the socket Lich
  # already has open and exchanges lines with it. See docs/decisions.md for
  # what was confirmed against lich-5's own listener source.
  class Connection
    # Raised when the initial connect attempt itself fails (host down,
    # nothing listening on the port, DNS failure). Never raised once
    # connected -- a mid-session drop is reported through on_disconnect
    # instead, so callers can tell the two apart.
    ConnectError = Class.new(StandardError)

    def initialize(host:, port:, on_line:, on_disconnect: nil)
      @host          = host
      @port          = port
      @on_line       = on_line
      @on_disconnect = on_disconnect
      @socket        = nil
      @write_mutex   = Mutex.new
    end

    def connect
      @socket = TCPSocket.new(@host, @port)
    rescue SystemCallError, SocketError => e
      raise ConnectError, "could not connect to #{@host}:#{@port}: #{e.message}"
    end

    def connected?
      !@socket.nil? && !@socket.closed?
    end

    # Sends SET_FRONTEND_PID, the optional identify line lich-5 recognizes
    # (see docs/decisions.md). Not required for the socket to work, but
    # lets Lich tell grimoire apart from other attached frontends.
    def identify(pid: Process.pid)
      send_line("SET_FRONTEND_PID #{pid}")
    end

    def send_line(line)
      return unless connected?

      @write_mutex.synchronize { @socket.puts(line) }
    end

    # Runs the blocking read loop on a new thread and returns it.
    def start_reading
      Thread.new { read_loop }
    end

    def close
      @socket&.close
    rescue IOError
      nil
    end

    private

    def read_loop
      while connected? && (line = @socket.gets)
        @on_line.call(line)
      end
      @on_disconnect&.call(:eof)
    rescue StandardError => e
      # Covers both socket-level failures and a raise from on_line itself --
      # either way the read loop is about to die, so this must not do so
      # silently on a background thread with no one watching.
      @on_disconnect&.call(:error, e)
    end
  end
end
