require 'gtk3'
require_relative 'connection'
require_relative 'command_queue'
require_relative 'narrative_stream'
require_relative 'session_logger'
require_relative 'theme'
require_relative 'window'

module Grimoire
  # Wires the socket layer (Connection, CommandQueue), the protocol layer
  # (NarrativeStream), and the Window together. Connection's read loop
  # runs on its own thread; handle_line and handle_disconnect fire there,
  # so both marshal into the GTK main thread via GLib::Idle.add before
  # touching the window.
  class App
    def initialize(host:, port:, autolog: false, log_dir: 'logs', prompt_char: NarrativeStream::DEFAULT_PROMPT_CHAR,
                   theme: Theme::DEFAULT)
      @prompt_char = prompt_char
      @narrative   = NarrativeStream.new(on_prompt: method(:handle_prompt), prompt_char: prompt_char)
      @window      = Window.new(on_command: method(:handle_command), theme: theme)
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

      GLib::Timeout.add(1000) do
        tick_roundtime
        true
      end

      @window.show
      Gtk.main
    end

    private

    # Vitals (including roundtime_end) only ever change on a line from
    # Connection's read thread, and handle_line already refreshes the strip
    # from them there -- but a countdown needs to visibly tick down between
    # lines too, with no new wire traffic to drive it. Runs on the GTK main
    # thread already (a GLib::Timeout callback, not a socket thread), so
    # unlike handle_line/handle_command it needs no GLib::Idle.add marshal
    # of its own.
    def tick_roundtime
      @window.update_vitals(@narrative.vitals_state)
    end

    # Lich's detachable-client protocol never echoes a submitted command
    # back over the wire (confirmed against real captured sessions -- see
    # docs/decisions.md), so the frontend is responsible for showing it;
    # ProfanityFE's own architecture confirms the same split (it echoes
    # locally on send rather than waiting on anything from the server).
    def handle_command(command)
      display("\n#{@prompt_char} #{command}\n")
      @command_queue.enqueue(command)
    end

    # Lich's initial push on connect covers vitals/indicators/exits but not
    # room description/objects/players (see docs/decisions.md), so the
    # first prompt grimoire sees is the cue to ask for them itself. Fires
    # from Connection's read-loop thread same as handle_line; handle_command
    # already marshals its own widget write through #display, so no extra
    # marshaling is needed here.
    def handle_prompt(_time)
      return if @looked_up

      @looked_up = true
      handle_command('look')
    end

    # Vitals arrive on lines that carry no narrative text at all (a bare
    # self-closing <progressBar>/<indicator>), so the vitals refresh cannot
    # be gated behind `text.empty?` the way the scrollback append is --
    # every line refreshes the strip from the live VitalsState, cheap
    # enough (a handful of label/fraction writes) that no dirty-tracking
    # is needed.
    def handle_line(line)
      @session_logger&.raw(line)
      text = @narrative.feed(line)
      @session_logger&.parsed(text)

      GLib::Idle.add do
        @window.update_vitals(@narrative.vitals_state)
        @window.append_text(text) unless text.empty?
        false
      end
    end

    def handle_disconnect(reason, error = nil)
      @session_logger&.close
      detail = error ? "#{reason} - #{error.message}" : reason.to_s
      display("\n[disconnected: #{detail}]\n")
    end

    def handle_send_error(error)
      display("\n[send error: #{error.message}]\n")
    end

    # The only path for locally-generated lines (command echoes,
    # disconnect/send-error notices) that never flow through handle_line,
    # so it is also the only place responsible for writing them into the
    # parsed session log -- without this, a typed command's own echo was
    # visible live in the scrollback but silently absent from the parsed
    # log file, even though the command's *response* (arriving over the
    # wire, logged by handle_line) was present, making the log look like
    # it appeared unprompted.
    def display(text)
      @session_logger&.parsed(text)

      GLib::Idle.add do
        @window.append_text(text)
        false
      end
    end
  end
end
