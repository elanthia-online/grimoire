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

    # The inverse of .from_hex -- "#rrggbb", lowercase, always 2 digits per
    # channel. Used by ConfigTemplate to render a Theme back out as
    # config.yml/defaults.yml, the format those files (and most color
    # pickers) already speak, rather than the red:/green:/blue: triple form
    # this class uses internally.
    def to_hex
      format('#%02x%02x%02x', red, green, blue)
    end
  end
end
