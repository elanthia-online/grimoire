require_relative 'tokenizer'
require_relative 'stream_tracker'

module Grimoire
  # Combines Tokenizer and StreamTracker to turn a raw chunk off the wire
  # into the narrative-only text a scrollback pane should display,
  # dropping any text that arrived inside a pushStream/popStream block
  # (inventory, room objs/players, dialog panels, etc.). Those panel tags
  # are only discarded here, not routed anywhere yet -- structured room
  # state is a separate, still-open TASKS.md item.
  class NarrativeStream
    def initialize
      @tokenizer = Tokenizer.new
      @tracker   = StreamTracker.new
    end

    def feed(chunk)
      @tokenizer.feed(chunk).filter_map { |token| narrative_value(token) }.join
    end

    private

    def narrative_value(token)
      routed = @tracker.route(token)
      return nil unless routed.narrative?
      return nil unless token.is_a?(Tokenizer::Tokens::Text)

      token.value
    end
  end
end
