module Grimoire
  # Rewrites grimoire's local ".command" shorthand into Lich's actual
  # script-command prefix (";command", or "," for Genie -- see
  # docs/decisions.md). Purely a local UX convenience: typing ";command"
  # directly works with no rewriting at all, this just saves a keystroke.
  module CommandRewrite
    LOCAL_PREFIX = '.'.freeze
    LICH_PREFIX  = ';'.freeze

    def self.call(input)
      return input unless input.start_with?(LOCAL_PREFIX)

      "#{LICH_PREFIX}#{input[1..]}"
    end
  end
end
