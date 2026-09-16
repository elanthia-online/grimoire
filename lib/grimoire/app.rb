require 'gtk3'
require_relative 'narrative_stream'
require_relative 'session'
require_relative 'theme'
require_relative 'window'

module Grimoire
  # Pairs one character's Session with the Window it draws into, and owns
  # the GTK main loop. Everything per-character -- socket, command queue,
  # protocol layer, session log, and the marshaling of all three onto the
  # GTK main thread -- now lives in Session (lib/grimoire/session.rb);
  # App is just the single-session shell wrapped around exactly one of
  # them, and is what the multi-session shell replaces once it can hold N
  # (see TASKS.md's "Multi-session shell" section).
  class App
    # How often the roundtime countdown is refreshed between wire lines,
    # in milliseconds -- see Session#tick for why this is driven from out
    # here rather than from the socket thread.
    ROUNDTIME_TICK_INTERVAL = 1000

    attr_reader :session

    def initialize(host:, port:, character: nil, autolog: false, log_dir: 'logs',
                   prompt_char: NarrativeStream::DEFAULT_PROMPT_CHAR, theme: Theme::DEFAULT)
      # The callback closes over @session rather than referencing it
      # directly, since the window has to exist before the session that
      # draws into it can be built. Nothing calls it until the user
      # submits a command, by which point @session is set.
      @window  = Window.new(on_command: ->(command) { @session.send_command(command) }, theme: theme)
      @session = Session.new(
        host: host,
        port: port,
        character: character,
        view: @window,
        autolog: autolog,
        log_dir: log_dir,
        prompt_char: prompt_char
      )
    end

    def run
      @session.start

      GLib::Timeout.add(ROUNDTIME_TICK_INTERVAL) do
        @session.tick
        true
      end

      @window.show
      Gtk.main
    end
  end
end
