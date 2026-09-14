require_relative 'tokenizer'

module Grimoire
  # Tags each Tokenizer token with the stream id it belongs to, so a
  # consumer can tell narrative text (stream_id nil) apart from text that
  # arrived inside a pushStream/popStream block (inventory, room objs/
  # players, dialog panels, etc.) without guessing from bare close tags.
  #
  # This mirrors lich-5's own confirmed xmlparser.rb behavior (see
  # docs/decisions.md): pushStream/popStream track a single current-stream
  # value, not a nested stack. A pushStream seen while already inside a
  # stream simply overwrites the current id, and popStream always returns
  # to narrative (nil) regardless of any id it carries -- the real
  # protocol never nests streams, so there is nothing to restore.
  class StreamTracker
    Routed = Data.define(:token, :stream_id) do
      def narrative?
        stream_id.nil?
      end
    end

    def initialize
      @current_stream = nil
    end

    def route(token)
      return pop(token) if pop_stream?(token)

      push(token) if push_stream?(token)
      Routed.new(token: token, stream_id: @current_stream)
    end

    private

    def push_stream?(token)
      tag?(token) && token.name == 'pushStream'
    end

    def pop_stream?(token)
      tag?(token) && token.name == 'popStream'
    end

    def tag?(token)
      token.is_a?(Tokenizer::Tokens::Tag)
    end

    def push(token)
      @current_stream = token.attrs['id']
    end

    def pop(token)
      closing_stream = @current_stream
      @current_stream = nil
      Routed.new(token: token, stream_id: closing_stream)
    end
  end
end
