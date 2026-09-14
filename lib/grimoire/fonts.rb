require 'gtk3'

module Grimoire
  # Registers grimoire's bundled font files (assets/fonts/**/*.ttf|*.otf)
  # with Pango at process startup, via Pango::FontMap#add_font_file --
  # added in Pango 1.52 specifically so an app can ship its own fonts and
  # use them without a system-wide install, across every Pango font
  # backend (fontconfig on Linux, DirectWrite on Windows, CoreText on
  # macOS) rather than the older fontconfig-only FcConfigAppFontAddFile
  # trick, which only ever covered Linux. Confirmed working end-to-end
  # even with fontconfig pointed at a config with zero system font
  # directories (i.e. the font is genuinely usable with nothing installed
  # on the host at all, not merely "found faster") -- see the config
  # investigation this module grew out of, 2026-09-13.
  #
  # assets/fonts/ ships empty in the repo (see assets/fonts/README.md) --
  # #load_bundled! is a deliberate no-op with nothing dropped in yet, not
  # an error, and Theme::DEFAULT's font family already carries a generic
  # `monospace` fallback for exactly that case. A Pango build older than
  # 1.52 has no add_font_file method at all; that is caught the same way
  # -- grimoire falls back to whatever font family the system already has.
  module Fonts
    DIR = File.expand_path('../../assets/fonts', __dir__)

    def self.load_bundled!(font_map: Pango::CairoFontMap.default)
      font_files.each { |path| font_map.add_font_file(path) }
    rescue NoMethodError
      warn 'grimoire: Pango::FontMap#add_font_file unavailable (needs Pango >= 1.52) -- ' \
           'bundled fonts in assets/fonts/ were not loaded'
    end

    def self.font_files
      return [] unless Dir.exist?(DIR)

      Dir.glob(File.join(DIR, '**', '*.{ttf,otf}'))
    end
  end
end
