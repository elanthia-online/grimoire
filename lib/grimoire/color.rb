module Grimoire
  # A plain RGB triple, standard 0-255 per channel. #to_css renders it in
  # the "rgb(r, g, b)" form GTK's CSS provider expects -- see Theme/Window's
  # vitals-strip and main-window styling, the only current consumers.
  Color = Data.define(:red, :green, :blue) do
    # Parses a "#rrggbb" (or bare "rrggbb") string, the form config.yml uses
    # since it is what CSS/most color pickers already speak -- raises
    # ArgumentError on anything else so a typo in a user's config file fails
    # loudly at load time (see Config) rather than silently drawing black.
    def self.from_hex(hex)
      match = /\A#?(\h{2})(\h{2})(\h{2})\z/.match(hex.to_s)
      raise ArgumentError, "invalid color: #{hex.inspect} (expected \"#rrggbb\")" unless match

      new(*match.captures.map { |part| part.to_i(16) })
    end

    def to_css
      "rgb(#{red}, #{green}, #{blue})"
    end
  end
end
