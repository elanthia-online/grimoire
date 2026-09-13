require_relative 'tokenizer'
require_relative 'stream_tracker'
require_relative 'prompt_tracker'
require_relative 'room_tracker'
require_relative 'room_state'
require_relative 'panel_tag_tracker'
require_relative 'vitals_tracker'
require_relative 'vitals_state'

module Grimoire
  # Combines Tokenizer, StreamTracker, PromptTracker, RoomTracker and
  # PanelTagTracker to turn a raw chunk off the wire into the
  # narrative-only text a scrollback pane should display: text inside a
  # pushStream/popStream block (inventory, dialog panels, etc.) is dropped
  # without being routed anywhere yet -- routing dialogData/openDialog/inv
  # to structured state remains a separate, still-open TASKS.md item --
  # room desc/objs/players/exits are dropped from narrative and routed
  # into #room_state instead (see docs/decisions.md), the "&gt;" inside a
  # <prompt time="..."> bracket is squelched the same way, recognized
  # vitals/status progressBar and indicator tags are dropped from narrative
  # and routed into #vitals_state instead (see VitalsTracker), and a fixed
  # set of remaining GUI-panel/status tags (dialogData, spell, roommeta,
  # etc. -- see PanelTagTracker) are squelched outright as a temporary,
  # evidence-based measure. on_prompt, if given, fires once per closed
  # prompt tag with
  # its captured time, letting a caller act on each prompt (e.g.
  # auto-sending `look` on the first one to populate initial room state,
  # per TASKS.md -- Lich's own initial push does not include it).
  #
  # Also handles the leading line terminator that a fully-squelched tag (a
  # lone <prompt>, a bare <component id='room objs'>, or a whole pushStream/
  # popStream bracket) leaves behind. Lich delivers one wire line per read,
  # each still carrying its own CRLF, and a squelched tag that occupies an
  # entire line leaves that line's own terminator as a separate, ordinary
  # Text token arriving *after* the tracker has already flipped back to
  # narrative -- so nothing upstream would otherwise recognize it as
  # belonging to the squelched line rather than to new content.
  #
  # Before any real narrative text has ever been seen, that terminator is
  # pure noise (nothing to separate yet) and is dropped -- otherwise a
  # squelch-only fixture, or a squelched tag right at the start of a
  # session, would leak a leading blank line. Once real narrative text has
  # appeared, though, that same terminator is kept as the one separator
  # between the narrative before the squelch and whatever narrative comes
  # after it -- sibling project rift-nexus's own <prompt> handling shows why
  # this needs to be capped at exactly one rather than left alone entirely:
  # a run of several squelched lines in a row (a <prompt> immediately
  # followed by a <component> refresh, say) must not turn into several
  # stacked blank lines, only the single one a reader expects between two
  # completed outputs. A later, separate, genuinely blank line in real
  # narrative text (the game itself sending an empty line) is left alone
  # either way and never stacks a second blank line on top of this one.
  class NarrativeStream
    # A ">>> <command>" narrative line was initially assumed to be Lich
    # echoing a submitted command back over the wire (based on a sample in
    # _references/session-logs), rewritten here to "<prompt_char> <command>"
    # accordingly. Two real `--autolog` captures against an actual Lich
    # frontend-port connection (log/session-8000-20260913-{161027,165033},
    # not committed -- see .gitignore) showed this is wrong: Lich's
    # detachable-client protocol never echoes a submitted command back at
    # all, over the wire or otherwise -- see docs/decisions.md. The rewrite
    # is left in place as a harmless no-op safeguard (nothing on real
    # traffic matches it), but `App#handle_command`'s own local echo, not
    # this, is the confirmed mechanism for showing a typed command.
    # DEFAULT_PROMPT_CHAR is the fallback rendering both share; making it
    # selectable beyond the default is a later task.
    DEFAULT_PROMPT_CHAR = '>'
    COMMAND_ECHO_PATTERN = /\A>>> /.freeze

    def initialize(on_prompt: nil, room_state: RoomState.new, vitals_state: VitalsState.new,
                   prompt_char: DEFAULT_PROMPT_CHAR)
      @tokenizer             = Tokenizer.new
      @stream_tracker        = StreamTracker.new
      @prompt_tracker        = PromptTracker.new
      @room_tracker          = RoomTracker.new(room_state: room_state)
      @panel_tracker         = PanelTagTracker.new
      @vitals_tracker        = VitalsTracker.new(vitals_state: vitals_state)
      @on_prompt             = on_prompt
      @prompt_char           = prompt_char
      @previously_narrative  = true
      @pending_boundary      = false
      @seen_real_content     = false
      @gap_separator_emitted = false
      @at_line_start         = true
    end

    def room_state
      @room_tracker.room_state
    end

    def vitals_state
      @vitals_tracker.vitals_state
    end

    def feed(chunk)
      @tokenizer.feed(chunk).filter_map { |token| narrative_value(token) }.join
    end

    private

    def narrative_value(token)
      stream_routed = @stream_tracker.route(token)
      prompt_routed = @prompt_tracker.route(token)
      room_routed   = @room_tracker.route(token)
      panel_routed  = @panel_tracker.route(token)
      vitals_routed = @vitals_tracker.route(token)
      notify_prompt(token)

      narrative = stream_routed.narrative? && prompt_routed.narrative? && room_routed.narrative? &&
                  panel_routed.narrative? && vitals_routed.narrative?
      @pending_boundary = true if narrative && !@previously_narrative
      @previously_narrative = narrative

      return nil unless narrative
      return nil unless token.is_a?(Tokenizer::Tokens::Text)

      resolve_boundary(rewrite_command_echo(token.value))
    end

    def rewrite_command_echo(value)
      value.sub(COMMAND_ECHO_PATTERN, "#{@prompt_char} ")
    end

    # A Text token that is purely a line terminator means two different
    # things depending on where it lands. If the narrative text just before
    # it did not already end in its own newline (e.g. the trailing "\r\n"
    # of "Obvious paths: <a...>out</a>\r\n", split into its own token by the
    # </a> boundary), this terminator is just that same line finishing --
    # not a blank row -- and always passes through untouched. Only when we
    # are already sitting at the start of a fresh line does another
    # newline-only token represent an actual blank row, and that is where
    # the squelch/separator bookkeeping below applies: before any real
    # narrative text has ever been seen, an artifact terminator (right at a
    # squelch-ending transition) is pure noise and dropped -- there is
    # nothing yet to separate -- and once real narrative text has appeared,
    # both an artifact terminator and a later, genuinely blank row the game
    # itself sends are capped to at most one surviving blank row per gap
    # between two pieces of real content, so neither a run of several
    # squelched lines in a row nor a squelched line immediately followed by
    # a real blank row stacks up more than the single separator a reader
    # expects between two completed outputs.
    def resolve_boundary(value)
      blank   = value.match?(/\A[\r\n]*\z/)
      pending = @pending_boundary
      @pending_boundary = false

      result =
        if blank && !@at_line_start
          value
        elsif pending
          blank ? artifact_separator(value) : value
        elsif blank
          genuine_blank(value)
        else
          @seen_real_content     = true
          @gap_separator_emitted = false
          value
        end

      @at_line_start = result.empty? || result.end_with?("\n")
      result
    end

    # An artifact terminator only ever becomes the gap's one separator once
    # real narrative text has been seen at least once; otherwise (a
    # squelch-only fixture, or a squelch right at the start of a session)
    # it is pure noise with nothing yet to separate.
    def artifact_separator(value)
      return '' unless @seen_real_content

      genuine_blank(value)
    end

    # The first blank line in a gap since the last real content survives
    # unconditionally (whether it is an artifact terminator once past the
    # @seen_real_content gate, or a genuinely blank line the game itself
    # sent); any further one before real content resumes is suppressed.
    def genuine_blank(value)
      if @gap_separator_emitted
        ''
      else
        @gap_separator_emitted = true
        value
      end
    end

    def notify_prompt(token)
      return unless @on_prompt
      return unless token.is_a?(Tokenizer::Tokens::Tag) && token.name == 'prompt' && token.closing

      @on_prompt.call(@prompt_tracker.last_time)
    end
  end
end
