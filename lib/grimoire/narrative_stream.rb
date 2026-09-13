require_relative 'tokenizer'
require_relative 'stream_tracker'
require_relative 'prompt_tracker'

module Grimoire
  # Combines Tokenizer, StreamTracker and PromptTracker to turn a raw chunk
  # off the wire into the narrative-only text a scrollback pane should
  # display: text inside a pushStream/popStream block (inventory, room
  # objs/players, dialog panels, etc.) is dropped here without being routed
  # anywhere yet -- structured room state is a separate, still-open
  # TASKS.md item -- and the "&gt;" inside a <prompt time="..."> bracket is
  # squelched the same way. on_prompt, if given, fires once per closed
  # prompt tag with its captured time, letting a caller act on each prompt
  # (e.g. auto-sending `look` on the first one to populate initial room
  # state, per TASKS.md -- Lich's own initial push does not include it, see
  # docs/decisions.md).
  class NarrativeStream
    def initialize(on_prompt: nil)
      @tokenizer      = Tokenizer.new
      @stream_tracker = StreamTracker.new
      @prompt_tracker = PromptTracker.new
      @on_prompt      = on_prompt
    end

    def feed(chunk)
      @tokenizer.feed(chunk).filter_map { |token| narrative_value(token) }.join
    end

    private

    def narrative_value(token)
      stream_routed = @stream_tracker.route(token)
      prompt_routed = @prompt_tracker.route(token)
      notify_prompt(token)

      return nil unless stream_routed.narrative? && prompt_routed.narrative?
      return nil unless token.is_a?(Tokenizer::Tokens::Text)

      token.value
    end

    def notify_prompt(token)
      return unless @on_prompt
      return unless token.is_a?(Tokenizer::Tokens::Tag) && token.name == 'prompt' && token.closing

      @on_prompt.call(@prompt_tracker.last_time)
    end
  end
end
