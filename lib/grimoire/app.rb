require 'gtk3'
require_relative 'connection'
require_relative 'command_queue'
require_relative 'narrative_stream'
require_relative 'session_logger'
require_relative 'window'

module Grimoire
  # Wires the socket layer (Connection, CommandQueue), the protocol layer
  # (NarrativeStream), and the Window together. Connection's read loop
  # runs on its own thread; handle_line and handle_disconnect fire there,
  # so both marshal into the GTK main thread via GLib::Idle.add before
  # touching the window.
  class App
    def initialize(host:, port:, autolog: false, log_dir: 'log')
      @narrative  = NarrativeStream.new(on_prompt: method(:handle_prompt))
      @window     = Window.new(on_command: method(:handle_command))
      @connection = Connection.new(
        host: host,
        port: port,
        on_line: method(:handle_line),
        on_disconnect: method(:handle_disconnect)
      )
      @command_queue  = CommandQueue.new(connection: @connection, on_error: method(:handle_send_error))
      @session_logger = autolog ? SessionLogger.new(dir: log_dir, port: port) : nil
      @looked_up = false
    end

    def run
      @connection.connect
      @connection.identify
      @connection.start_reading
      @command_queue.start

      @window.show
      Gtk.main
    end

    private

    def handle_command(command)
      @command_queue.enqueue(command)
    end

    # Lich's initial push on connect covers vitals/indicators/exits but not
    # room description/objects/players (see docs/decisions.md), so the
    # first prompt grimoire sees is the cue to ask for them itself. Fires
    # from Connection's read-loop thread same as handle_line, but enqueue
    # only touches the thread-safe command queue, not GTK widgets, so no
    # GLib::Idle.add marshaling is needed here.
    def handle_prompt(_time)
      return if @looked_up

      @looked_up = true
      handle_command('look')
    end

    def handle_line(line)
      @session_logger&.raw(line)
      text = @narrative.feed(line)
      @session_logger&.parsed(text)
      return if text.empty?

      display(text)
    end

    def handle_disconnect(reason, error = nil)
      @session_logger&.close
      detail = error ? "#{reason} - #{error.message}" : reason.to_s
      display("\n[disconnected: #{detail}]\n")
    end

    def handle_send_error(error)
      display("\n[send error: #{error.message}]\n")
    end

    def display(text)
      GLib::Idle.add do
        @window.append_text(text)
        false
      end
    end
  end
end
