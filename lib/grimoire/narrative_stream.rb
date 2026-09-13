require_relative 'tokenizer'
require_relative 'stream_tracker'
require_relative 'prompt_tracker'
require_relative 'room_tracker'
require_relative 'room_state'
require_relative 'panel_tag_tracker'

module Grimoire
  # Combines Tokenizer, StreamTracker, PromptTracker, RoomTracker and
  # PanelTagTracker to turn a raw chunk off the wire into the
  # narrative-only text a scrollback pane should display: text inside a
  # pushStream/popStream block (inventory, dialog panels, etc.) is dropped
  # without being routed anywhere yet -- routing dialogData/openDialog/inv
  # to structured state remains a separate, still-open TASKS.md item --
  # room desc/objs/players/exits are dropped from narrative and routed
  # into #room_state instead (see docs/decisions.md), the "&gt;" inside a
  # <prompt time="..."> bracket is squelched the same way, and a fixed set
  # of GUI-panel/status tags (dialogData, spell, roommeta, etc. -- see
  # PanelTagTracker) are squelched outright as a temporary, evidence-based
  # measure. on_prompt, if given, fires once per closed prompt tag with
  # its captured time, letting a caller act on each prompt (e.g.
  # auto-sending `look` on the first one to populate initial room state,
  # per TASKS.md -- Lich's own initial push does not include it).
  #
  # Also strips exactly one leading line terminator off the first narrative
  # text after any squelch ends. Lich delivers one wire line per read, each
  # still carrying its own CRLF, and a fully-squelched tag (a lone
  # <prompt>, a bare <component id='room objs'>, or a whole pushStream/
  # popStream bracket) that occupies an entire line leaves that line's own
  # terminator as a separate, ordinary Text token arriving *after* the
  # tracker has already flipped back to narrative -- so nothing upstream
  # would otherwise recognize it as belonging to the squelched line rather
  # than to new content. Left unhandled, this produces a blank line per
  # squelched line -- sibling project rift-nexus hit exactly this with
  # <prompt> (resent far more often than once per action) before fixing it
  # with a display-side regex collapse; grimoire's tokenizer already knows
  # the real tag boundaries, so the fix here is to swallow that one
  # known-orphaned terminator at the source instead of collapsing blank
  # runs after the fact -- a later, deliberate blank line in real narrative
  # text is left alone.
  class NarrativeStream
    def initialize(on_prompt: nil, room_state: RoomState.new)
      @tokenizer            = Tokenizer.new
      @stream_tracker       = StreamTracker.new
      @prompt_tracker       = PromptTracker.new
      @room_tracker         = RoomTracker.new(room_state: room_state)
      @panel_tracker        = PanelTagTracker.new
      @on_prompt            = on_prompt
      @previously_narrative = true
      @pending_line_strip   = false
    end

    def room_state
      @room_tracker.room_state
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
      notify_prompt(token)

      narrative = stream_routed.narrative? && prompt_routed.narrative? && room_routed.narrative? &&
                  panel_routed.narrative?
      @pending_line_strip = true if narrative && !@previously_narrative
      @previously_narrative = narrative

      return nil unless narrative
      return nil unless token.is_a?(Tokenizer::Tokens::Text)

      strip_orphaned_terminator(token.value)
    end

    def strip_orphaned_terminator(value)
      return value unless @pending_line_strip

      @pending_line_strip = false
      value.sub(/\A\r?\n/, '')
    end

    def notify_prompt(token)
      return unless @on_prompt
      return unless token.is_a?(Tokenizer::Tokens::Tag) && token.name == 'prompt' && token.closing

      @on_prompt.call(@prompt_tracker.last_time)
    end
  end
end
