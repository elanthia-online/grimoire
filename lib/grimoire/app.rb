require 'gtk3'
require_relative 'connection'
require_relative 'command_queue'
require_relative 'narrative_stream'
require_relative 'window'

module Grimoire
  # Wires the socket layer (Connection, CommandQueue), the protocol layer
  # (NarrativeStream), and the Window together. Connection's read loop
  # runs on its own thread; handle_line and handle_disconnect fire there,
  # so both marshal into the GTK main thread via GLib::Idle.add before
  # touching the window.
  class App
    def initialize(host:, port:)
      @narrative  = NarrativeStream.new
      @window     = Window.new(on_command: method(:handle_command))
      @connection = Connection.new(
        host: host,
        port: port,
        on_line: method(:handle_line),
        on_disconnect: method(:handle_disconnect)
      )
      @command_queue = CommandQueue.new(connection: @connection, on_error: method(:handle_send_error))
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

    def handle_line(line)
      text = @narrative.feed(line)
      return if text.empty?

      display(text)
    end

    def handle_disconnect(reason, error = nil)
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
