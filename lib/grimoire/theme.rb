require_relative 'color'

module Grimoire
  # The full set of user-configurable appearance settings: the main
  # scrollback/entry background and text color, the scrollback font, and
  # the vitals-strip/roundtime-bar fill colors. Config.load builds one of
  # these from config.yml, falling back field-by-field to DEFAULT so a
  # config file only needs to mention the settings it wants to override.
  #
  # DEFAULT's vitals_colors/roundtime_hard/roundtime_cast values are the
  # same fixed constants the former VitalsColors module carried (see
  # docs/decisions.md's entry on that module for the reasoning behind the
  # per-field choices: red for health, blue for mana, etc.) -- this class
  # takes over that role now that a settings file exists to override them,
  # per TASKS.md's "User-selectable/configurable vitals-strip colors" item.
  # main_background/main_foreground default to black-on-white per the
  # user's own spec for the primary input/output windows (2026-09-13).
  # font_family defaults to Overpass Mono with a generic monospace
  # fallback -- the user's stated preferred default (2026-09-13), since
  # Overpass Mono is open source/freely redistributable but, unlike
  # "Monospace"'s usual fallback candidates, is not preinstalled on
  # Windows. Grimoire.rb wires Grimoire::Fonts.load_bundled! (see
  # lib/grimoire/fonts.rb) to register any font files under assets/fonts/
  # with Pango at startup, so this default works out of the box once those
  # fonts are dropped in there, without a system-wide font install -- and
  # falls back to the generic "monospace" family cleanly if they are not.
  Theme = Data.define(
    :main_background, :main_foreground, :font_family, :font_size,
    :vitals_colors, :vitals_background, :roundtime_hard, :roundtime_cast
  )

  # Reopened as a plain class body (rather than continuing Data.define's own
  # block) so DEFAULT's constant assignment lands on Theme itself --
  # assigning a constant inside Data.define's block instead follows the
  # block's lexical scope (Grimoire), silently defining Grimoire::DEFAULT
  # rather than Grimoire::Theme::DEFAULT, confirmed while writing this.
  class Theme
    DEFAULT = new(
      main_background: Color.new(red: 0, green: 0, blue: 0),
      main_foreground: Color.new(red: 255, green: 255, blue: 255),
      font_family: 'Overpass Mono, monospace',
      font_size: 11,
      vitals_colors: {
        :health      => Color.new(red: 200, green: 0,   blue: 0),
        :mana        => Color.new(red: 0,   green: 0,   blue: 200),
        :stamina     => Color.new(red: 200, green: 160, blue: 0),
        :spirit      => Color.new(red: 200, green: 200, blue: 200),
        :mind        => Color.new(red: 128, green: 0,   blue: 200),
        :encumbrance => Color.new(red: 150, green: 150, blue: 150),
        :stance      => Color.new(red: 150, green: 150, blue: 150),
      }.freeze,
      vitals_background: Color.new(red: 0, green: 0, blue: 0),
      roundtime_hard: Color.new(red: 200, green: 0, blue: 0),
      roundtime_cast: Color.new(red: 0, green: 0, blue: 200)
    )
  end
end
