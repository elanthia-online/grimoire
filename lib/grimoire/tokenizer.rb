module Grimoire
  class Tokenizer
    module Tokens
      Text = Data.define(:value)
      Tag  = Data.define(:name, :attrs, :closing, :self_closing)
    end

    # Minimum literal entity set per TASKS.md -- expand here if the game
    # stream is found to rely on others.
    ENTITIES = {
      '&gt;'   => '>',
      '&lt;'   => '<',
      '&amp;'  => '&',
      '&apos;' => "'",
      '&quot;' => '"',
    }.freeze

    ENTITY_PATTERN = Regexp.union(ENTITIES.keys).freeze
    ATTR_PATTERN   = /([^\s=]+)\s*=\s*(?:"([^"]*)"|'([^']*)')/.freeze

    def initialize
      @buffer = String.new
    end

    # Feeds a raw chunk read off the socket and returns the tokens that
    # could be completed with it. A tag or entity left incomplete at the
    # end of the chunk stays buffered rather than being emitted early or
    # dropped -- the caller just needs to keep feeding chunks in order.
    def feed(chunk)
      @buffer << chunk
      tokens = []

      loop do
        token, consumed = next_token
        break unless token

        @buffer = @buffer[consumed..]
        tokens << token
      end

      tokens
    end

    private

    def next_token
      return nil if @buffer.empty?

      @buffer.start_with?('<') ? tag_token : text_token
    end

    def tag_token
      close_index = find_tag_close(@buffer)
      return nil unless close_index # incomplete tag -- wait for more data

      raw = @buffer[0..close_index]
      [parse_tag(raw), raw.length]
    end

    # Finds the '>' that ends the tag starting at buffer[0], skipping any
    # '>' that appears inside a quoted attribute value. Returns nil when
    # the buffer does not yet contain the whole tag.
    def find_tag_close(str)
      in_quote = nil

      (1...str.length).each do |i|
        char = str[i]
        if in_quote
          in_quote = nil if char == in_quote
        elsif char == '"' || char == "'"
          in_quote = char
        elsif char == '>'
          return i
        end
      end

      nil
    end

    def parse_tag(raw)
      closing      = raw.start_with?('</')
      self_closing = raw.end_with?('/>')
      inner        = raw.sub(%r{\A</?}, '').sub(%r{/?>\z}, '').strip

      name, attr_str = inner.split(/\s+/, 2)
      Tokens::Tag.new(
        name: name.to_s,
        attrs: parse_attrs(attr_str),
        closing: closing,
        self_closing: self_closing
      )
    end

    def parse_attrs(attr_str)
      return {} unless attr_str

      attr_str.scan(ATTR_PATTERN).each_with_object({}) do |(key, dquoted, squoted), attrs|
        attrs[key] = decode_entities(dquoted || squoted || '')
      end
    end

    def text_token
      lt_index = @buffer.index('<')

      if lt_index
        # The boundary is certain -- whatever precedes '<' is the whole
        # text run, entity or not.
        text = @buffer[0...lt_index]
        [Tokens::Text.new(value: decode_entities(text)), text.length]
      else
        safe_length = safe_text_length(@buffer)
        return nil if safe_length.zero?

        text = @buffer[0...safe_length]
        [Tokens::Text.new(value: decode_entities(text)), safe_length]
      end
    end

    # With no '<' in sight yet, a trailing unterminated '&' might be the
    # front half of an entity split across a TCP read -- hold it and
    # everything after it back rather than emitting it undecoded.
    def safe_text_length(candidate)
      amp_index = candidate.rindex('&')
      return candidate.length unless amp_index
      return candidate.length if candidate.index(';', amp_index)

      amp_index
    end

    def decode_entities(text)
      text.gsub(ENTITY_PATTERN, ENTITIES)
    end
  end
end
