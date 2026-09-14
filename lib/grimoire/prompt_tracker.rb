require_relative 'tokenizer'

module Grimoire
  # Tracks <prompt time="..">...</prompt> brackets. These arrive at
  # narrative level -- not inside any pushStream/popStream (confirmed in
  # spec/fixtures/room_update.xml) -- but the enclosed "&gt;" is the game's
  # live-input marker, not narrative text, so it needs its own bracket
  # tracking rather than reusing StreamTracker's id-keyed one.
  class PromptTracker
    Routed = Data.define(:token, :in_prompt) do
      def narrative?
        !in_prompt
      end
    end

    attr_reader :last_time

    def initialize
      @in_prompt = false
      @last_time = nil
    end

    def route(token)
      return mark_open(token) if open_prompt?(token)
      return mark_close(token) if close_prompt?(token)

      Routed.new(token: token, in_prompt: @in_prompt)
    end

    private

    def prompt_tag?(token)
      token.is_a?(Tokenizer::Tokens::Tag) && token.name == 'prompt'
    end

    def open_prompt?(token)
      prompt_tag?(token) && !token.closing
    end

    def close_prompt?(token)
      prompt_tag?(token) && token.closing
    end

    def mark_open(token)
      @in_prompt = true
      @last_time = token.attrs['time']
      Routed.new(token: token, in_prompt: true)
    end

    def mark_close(token)
      was_in_prompt = @in_prompt
      @in_prompt = false
      Routed.new(token: token, in_prompt: was_in_prompt)
    end
  end
end
