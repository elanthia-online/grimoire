module Grimoire
  # A plain RGB triple, standard 0-255 per channel. #to_css renders it in
  # the "rgb(r, g, b)" form GTK's CSS provider expects -- see
  # VitalsColors/Window's vitals-strip styling, the only current consumer.
  Color = Data.define(:red, :green, :blue) do
    def to_css
      "rgb(#{red}, #{green}, #{blue})"
    end
  end
end
