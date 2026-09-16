require 'gtk3'
require_relative 'connection'
require_relative 'command_queue'
require_relative 'narrative_stream'
require_relative 'session_logger'

module Grimoire
  # One character's complete non-visual stack: the socket layer
  # (Connection, CommandQueue), the protocol layer (NarrativeStream and the
  # tracker chain behind it), and the optional session log. Owns every
  # callback those fire, and is the only place their results are marshaled
  # onto the GTK main thread -- Connection's read loop runs on its own
  # thread, so #handle_line and #handle_disconnect fire there and must
  # never touch a widget directly.
  #
  # Deliberately does not build its own view. Everything on-screen goes
  # through whatever #initialize was handed as `view:` (anything answering
  # #append_text and #update_vitals -- SessionView does), so one session stays
  # independent of whether its view is a top-level window, an embeddable
  # widget, or currently visible at all. That independence is what lets a
  # shell hold several of these at once; see TASKS.md's "Multi-session
  # shell" section.
  #
  # `character` is carried for the caller's benefit (naming a tab, keying
  # per-character config or logs) and is nil when grimoire was pointed at a
  # raw --host/--port with no name to go with it.
  class Session
    # Who started the Lich process behind this session, which decides what
    # the shell does when the connection drops (TASKS.md's "Multi-session
    # shell" item 7, the user's own call, 2026-09-16):
    #
    # - :attached -- Lich was already running and grimoire only attached to
    #   it. Marked disconnected, rescanned, reattached automatically.
    # - :launched_headless -- grimoire spawned `lich --headless`. Same
    #   treatment as :attached.
    # - :launched_with_frontend -- grimoire spawned Lich with a frontend of
    #   its own. The tab closes as soon as the connection drops.
    #
    # Only :attached is produced today; the two launch origins are for
    # BACKLOG.md's "Lich headless launch" section (and a hypothetical
    # non-headless launch) to pass in once that exists.
    ORIGINS = %i[attached launched_headless launched_with_frontend].freeze

    # host/port are this session's identity on the wire, and are what tells
    # two sessions apart when the character name is unknown (a raw
    # --host/--port attach) or shared -- see Shell's duplicate-attach guard.
    # They change on #reconnect, since a restarted Lich can bind a new port.
    attr_reader :character, :host, :port, :narrative, :origin

    # on_drop is called with this session, on the GTK main thread, when the
    # connection ends for any reason other than #stop -- a closed tab is not
    # a dropped session, and must not start the shell's reattach scan.
    def initialize(host:, port:, view:, character: nil, origin: :attached, on_drop: nil,
                   autolog: false, log_dir: 'logs', prompt_char: NarrativeStream::DEFAULT_PROMPT_CHAR)
      raise ArgumentError, "unknown session origin: #{origin.inspect}" unless ORIGINS.include?(origin)

      @character   = character
      @host        = host
      @port        = port
      @view        = view
      @origin      = origin
      @on_drop     = on_drop
      @autolog     = autolog
      @log_dir     = log_dir
      @prompt_char = prompt_char
      @narrative   = build_narrative
      @connection, @command_queue = build_link(host, port)
      @session_logger = build_logger
      @looked_up      = false
      @connected      = false
      @stopped        = false
    end

    # Opens the socket and starts both worker threads. Separate from
    # #initialize so a caller can construct a session (cheaply, touching
    # no network) before deciding to bring it up.
    def start
      @connection.connect
      bring_up
    end

    # True from a successful #start or #reconnect until the connection ends.
    def connected?
      @connected
    end

    # Brings a dropped session back up on host/port, which may differ from
    # the ones it had: a Lich using an `auto` detachable-client port (port 0,
    # OS-assigned) binds a different port each time it comes back, including
    # after its own --reconnect. Raises
    # Connection::ConnectError exactly as #start does, and in that case
    # leaves the session untouched so the caller can simply try again later.
    #
    # The scrollback and the vitals/room state carry over (the view is the
    # same one, and the new NarrativeStream is handed the same state
    # objects). The tokenizer and trackers themselves start fresh, since the
    # old socket may have died partway through a tag, and the first prompt
    # sends `look` again because the room may well have changed while
    # disconnected. With --autolog on, the reattached session starts a new
    # pair of log files; the old pair was closed when the connection dropped.
    def reconnect(host:, port:)
      connection, command_queue = build_link(host, port)
      connection.connect

      @command_queue.stop
      @connection.close
      @host, @port                = host, port
      @connection, @command_queue = connection, command_queue
      @narrative      = build_narrative(room_state: @narrative.room_state, vitals_state: @narrative.vitals_state)
      @looked_up      = false
      @session_logger ||= build_logger
      display("\n[reattached: #{host}:#{port}]\n")
      bring_up
    end

    # Shuts this session down: stops the outgoing queue thread and closes the
    # socket, which ends Connection's read loop. That unwinding still fires
    # #handle_disconnect as usual, so the log is closed and the notice shown
    # by the same path an unexpected drop takes -- there is deliberately no
    # separate quiet teardown route to keep in sync with it.
    #
    # Without this, anything that builds a session leaves two live threads
    # behind holding a socket and scheduling GTK work through
    # GLib::Idle.add, which is exactly how the spec suite started crashing
    # intermittently once several sessions could exist at once.
    def stop
      @stopped = true
      @command_queue.stop
      @connection.close
    end

    # Lich's detachable-client protocol never echoes a submitted command
    # back over the wire (confirmed against real captured sessions -- see
    # docs/decisions.md), so the frontend is responsible for showing it;
    # ProfanityFE's own architecture confirms the same split (it echoes
    # locally on send rather than waiting on anything from the server).
    def send_command(command)
      display("\n#{@prompt_char} #{command}\n")
      @command_queue.enqueue(command)
    end

    # Vitals (including roundtime_end) only ever change on a line from
    # Connection's read thread, and #handle_line already refreshes the view
    # from them there -- but a countdown needs to visibly tick down between
    # lines too, with no new wire traffic to drive it. Callers drive this
    # from a repeating GLib::Timeout, whose callback already runs on the
    # GTK main thread, so unlike #handle_line/#send_command it needs no
    # GLib::Idle.add marshal of its own.
    def tick
      @view.update_vitals(@narrative.vitals_state)
    end

    private

    def bring_up
      @connection.identify
      @connection.start_reading
      @command_queue.start
      @connected = true
    end

    def build_narrative(**state)
      NarrativeStream.new(on_prompt: method(:handle_prompt), prompt_char: @prompt_char, **state)
    end

    # Each connection's callbacks only act while that connection is still
    # the current one. After a #reconnect the old read thread may still be
    # unwinding, and its final on_disconnect must not mark the freshly
    # reattached session as dropped again.
    def build_link(host, port)
      connection = nil
      connection = Connection.new(
        host: host,
        port: port,
        on_line: ->(line) { handle_line(line) if connection.equal?(@connection) },
        on_disconnect: ->(reason, error = nil) { handle_disconnect(reason, error) if connection.equal?(@connection) }
      )
      [connection, CommandQueue.new(connection: connection, on_error: method(:handle_send_error))]
    end

    def build_logger
      @autolog ? SessionLogger.new(dir: @log_dir, port: @port, character: @character) : nil
    end

    # Lich's initial push on connect covers vitals/indicators/exits but not
    # room description/objects/players (see docs/decisions.md), so the
    # first prompt grimoire sees is the cue to ask for them itself. Fires
    # from Connection's read-loop thread same as #handle_line;
    # #send_command already marshals its own widget write through #display,
    # so no extra marshaling is needed here.
    def handle_prompt(_time)
      return if @looked_up

      @looked_up = true
      send_command('look')
    end

    # Vitals arrive on lines that carry no narrative text at all (a bare
    # self-closing <progressBar>/<indicator>), so the vitals refresh cannot
    # be gated behind `text.empty?` the way the scrollback append is --
    # every line refreshes the view from the live VitalsState, cheap enough
    # (a handful of label/fraction writes) that no dirty-tracking is
    # needed.
    def handle_line(line)
      @session_logger&.raw(line)
      text = @narrative.feed(line)
      @session_logger&.parsed(text)

      GLib::Idle.add do
        @view.update_vitals(@narrative.vitals_state)
        @view.append_text(text) unless text.empty?
        false
      end
    end

    # The notice is emitted before the log is closed, not after. Closing
    # first meant #display's own `@session_logger&.parsed(text)` wrote to
    # an already-closed file and raised IOError, which (a) lost the
    # "[disconnected: ...]" line before it ever reached the view, since
    # the raise happens ahead of the GLib::Idle.add, and (b) propagated
    # back into Connection#read_loop's rescue, which called on_disconnect
    # a second time, raised again from inside the rescue, and killed the
    # read thread. Only ever reproduced with --autolog on -- with no
    # logger the `&.` short-circuits and nothing raises -- which is why it
    # went unnoticed. Emitting first also means the parsed log now records
    # why the session ended, which it never did before.
    #
    # The socket is closed here too: an EOF ends the read loop but leaves the
    # descriptor open. The drop is then handed to the shell, marshaled onto
    # the GTK main thread like every other view-facing callback, unless this
    # session was ended deliberately through #stop.
    def handle_disconnect(reason, error = nil)
      @connected = false
      detail = error ? "#{reason} - #{error.message}" : reason.to_s
      display("\n[disconnected: #{detail}]\n")
      @session_logger&.close
      @session_logger = nil
      @connection.close
      return if @stopped || @on_drop.nil?

      GLib::Idle.add do
        @on_drop.call(self)
        false
      end
    end

    def handle_send_error(error)
      display("\n[send error: #{error.message}]\n")
    end

    # The only path for locally-generated lines (command echoes,
    # disconnect/send-error notices) that never flow through #handle_line,
    # so it is also the only place responsible for writing them into the
    # parsed session log -- without this, a typed command's own echo was
    # visible live in the scrollback but silently absent from the parsed
    # log file, even though the command's *response* (arriving over the
    # wire, logged by #handle_line) was present, making the log look like
    # it appeared unprompted.
    def display(text)
      @session_logger&.parsed(text)

      GLib::Idle.add do
        @view.append_text(text)
        false
      end
    end
  end
end
