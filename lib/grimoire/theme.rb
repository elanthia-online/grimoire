require_relative 'color'

module Grimoire
  # The full set of user-configurable appearance settings: the game window's
  # (scrollback/entry) background and text color, the scrollback font, the
  # vitals-strip/roundtime-bar fill colors, the title bar colors, and the
  # layout padding/border settings. Config.load builds one of these from
  # config.yml, falling back field-by-field to DEFAULT so a config file only
  # needs to mention the settings it wants to override.
  #
  # Field naming: every foreground/background pair is abbreviated `_fg`/`_bg`
  # (game_window_fg/bg, title_bar_fg/bg, padding_bg) to mirror config.yml's
  # own `fg:`/`bg:` keys 1:1 -- the user's own spec (2026-09-13), who also
  # asked that config.yml itself spell the abbreviation out for readers (see
  # ConfigTemplate's own top-of-file note). Nothing else here is a
  # foreground/background pair (border_color, vitals_border_color, and the
  # per-vital fill colors are not abbreviated) so the convention is scoped to
  # exactly the fields it was asked for, not applied blanket-wide.
  #
  # DEFAULT's vitals_colors/roundtime_hard/roundtime_cast values are the
  # same fixed constants the former VitalsColors module carried (see
  # docs/decisions.md's entry on that module for the reasoning behind the
  # per-field choices: red for health, blue for mana, etc.) -- this class
  # takes over that role now that a settings file exists to override them,
  # per TASKS.md's "User-selectable/configurable vitals-strip colors" item.
  # game_window_bg/game_window_fg default to black-on-white per the user's
  # own spec for the primary input/output windows (2026-09-13); the field
  # (and config.yml's own section) was originally named `main`, renamed to
  # `game_window` per the user's own later spec (2026-09-13) to better name
  # what it actually is -- the scrollback/command-entry pair, i.e. the game
  # window, as distinct from grimoire's own top-level Gtk::Window (see
  # padding_bg below) or its title bar. font_family defaults to Overpass
  # Mono with a generic monospace fallback -- the user's stated preferred
  # default (2026-09-13), since Overpass Mono is open source/freely
  # redistributable but, unlike "Monospace"'s usual fallback candidates, is
  # not preinstalled on Windows. Grimoire.rb wires
  # Grimoire::Fonts.load_bundled! (see lib/grimoire/fonts.rb) to register
  # any font files under assets/fonts/ with Pango at startup, so this
  # default works out of the box once those fonts are dropped in there,
  # without a system-wide font install -- and falls back to the generic
  # "monospace" family cleanly if they are not.
  #
  # title_bar_bg/title_bar_fg theme a custom Gtk::HeaderBar (see
  # Window#build_titlebar) rather than the plain Gtk::Window title -- a
  # native window-manager-drawn title bar is not reliably restylable from
  # application CSS at all (it is the WM's own decoration, not a GTK
  # widget), so a themeable title bar means grimoire supplies its own via
  # Gtk::Window#set_titlebar, matching how most GTK3 apps expose a
  # themeable title bar. title_bar_fg still matches game_window_fg (white);
  # title_bar_bg defaults to a dark charcoal (#1a1a1a) one shade lighter
  # than game_window_bg's pure black rather than matching it exactly --
  # promoted from the user's own live-tuned config.yml (2026-09-13, see
  # padding/padding_bg below for the other two defaults promoted the same
  # way) as the new out-of-the-box baseline, giving the title bar a subtle
  # visual separation from the rest of the window instead of blending into
  # it completely.
  #
  # padding is a single global spacing/inset knob (px) -- not scoped to any
  # one widget the way every other field here is, so config.yml surfaces it
  # under its own top-level `global:` section rather than nested under
  # `game_window:` (where it used to live, back when that section was still
  # named `main:`). Per the user's own spec (2026-09-13, reported live
  # after padding_bg first shipped as window_background under its own
  # `window:` section: padding could already be resized but every widget's
  # own interior stayed flush against its border/edge regardless): padding
  # is applied twice over --
  #
  # - As the top-level layout's outer window border and the spacing between
  #   every one of its rows/gaps (vitals strip, scrollback, command row, the
  #   individual vital bars, and the vitals-strip/indicator-label gap) --
  #   its original role, unchanged.
  # - As CSS content padding *inside* every bordered widget (the scrollback
  #   text, the command entry, and the fill within each vitals-strip/
  #   roundtime progress bar's trough), so there is breathing room between a
  #   border and its own content too, not just between widgets. See
  #   Window#inset for how the vitals/roundtime bars keep their overall
  #   rendered size fixed (BAR_HEIGHT; ROUNDTIME_BAR_WIDTH/HEIGHT, the
  #   latter an exact match to GtkEntry's own height) while still growing
  #   this inset, by shrinking the trough's own CSS min-height/min-width to
  #   compensate rather than letting the bar grow past its target size.
  #
  # Default was originally 4, matching the fixed spacing every row already
  # used before this field existed, so that the *gaps*' look stayed
  # unchanged when this dual role first shipped; since then, retuned to 2
  # through the user's own live use and promoted from their config.yml as
  # the new baseline default (2026-09-13, see padding_bg/title_bar_bg for
  # the other two defaults promoted the same way) -- a tighter fit once
  # every bordered widget also gained its own inset from this same setting,
  # rather than the wider gap padding's original spacing-only role called
  # for. border_color/border_width
  # add an optional CSS frame around the scrollback/command-entry widgets;
  # vitals_border_color/vitals_border_width do the same for every
  # vitals-strip/roundtime bar's trough. Both border widths default to 0
  # (no visible border) so a config file only needs to set a width to opt
  # in. There is deliberately no vitals background field of any kind --
  # every progress bar's trough background is a fixed #000000 regardless of
  # any other color setting, the user's own spec (2026-09-13); see Window's
  # PROGRESS_BAR_BACKGROUND for where that constant actually lives.
  #
  # vitals_fg is the vitals-strip label text's own color (e.g. "Health
  # 253/355") -- previously not configurable at all, left at whatever the
  # system GTK theme's own default progressbar-text color happened to be,
  # the user's own spec (2026-09-13). Defaults to white for contrast
  # against the fixed #000000 progress-bar background (see the
  # PROGRESS_BAR_BACKGROUND note above). Unlike every other font on this
  # theme, the vitals label's font *family* is deliberately not a Theme
  # field at all -- the user explicitly asked for it to switch to plain
  # Overpass (not the Mono variant used elsewhere) without being made
  # configurable; see Window::VITALS_FONT_FAMILY, a plain string constant
  # #vital_css interpolates directly rather than reading off @theme, the
  # same pattern PROGRESS_BAR_BACKGROUND already uses for a setting that is
  # intentionally fixed rather than themeable.
  #
  # indicator_fg colors the active-status-indicator label (e.g. "STUNNED
  # BLEEDING", see Window#active_indicators) -- previously not configurable
  # at all, a bare Gtk::Label with no CSS class and no Theme field behind
  # it, rendering in whatever color the ambient GTK theme gave a plain
  # label. A single flat color, same shape as vitals_fg, rather than
  # per-indicator-type colors -- the user's own spec. Defaults to white,
  # matching vitals_fg and today's ambient look against the app's dark
  # theme.
  #
  # roundtime_fg colors the roundtime bar's overlaid "RT: <n>" text (see
  # Window#build_roundtime_bar) -- previously hardcoded to the CSS keyword
  # `white` directly in #roundtime_css, always white regardless of the
  # bar's own fill color underneath it (a still-valid design choice; see
  # that method's own comment), but with no Theme field or config.yml key
  # behind it at all. Defaults to white, preserving today's look.
  # font-weight stays a fixed `bold` in #roundtime_css, not themeable here
  # -- no spec asked for that to vary, same treatment VITALS_FONT_FAMILY
  # already gets for the vitals label's font.
  #
  # command_bar_bg/command_bar_fg/command_bar_font_family/command_bar_font_size
  # theme the command entry on its own, independent of game_window_bg/
  # game_window_fg/font_family/font_size -- the user's own spec (2026-09-13),
  # reported live: the command entry previously had no font setting at all
  # (Window#game_window_css only ever put font-family/font-size on the
  # scrollback textview, never on entry, so it silently rendered in the
  # system default font regardless of any config.yml font override) and no
  # independent color selection of its own (it borrowed game_window_bg/fg
  # outright, with no way to set the command bar's own colors without also
  # changing the scrollback's). Each defaults to its game_window counterpart
  # so the default look is unchanged; border_color/border_width/padding stay
  # shared between the scrollback and the command entry (`game_window.border`
  # in config.yml) since nothing has asked for those to split too.
  #
  # show_vitals_bar/show_roundtime_bar/show_status_bar gate whether
  # Window#build_vitals_strip/#build_roundtime_bar construct their widgets at
  # all, rather than building them and hiding the result -- per
  # BACKLOG.md's "Widget visibility toggles" item, config-file-only for now
  # (a restart is needed to pick up a change), not a live menu toggle.
  # show_status_bar governs the active-indicators label (e.g. "STUNNED
  # BLEEDING") specifically, independent of show_vitals_bar's health/mana/
  # stamina/etc bars -- both live in the same vertical strip
  # (#build_vitals_strip) but toggle separately, matching how indicator_fg
  # is already its own field independent of vitals_fg. All three default to
  # true so today's always-on layout is unchanged out of the box.
  #
  # padding_bg paints the Gtk::Window itself, which is what actually shows
  # through padding's own gaps (the outer border and the spacing between
  # the vitals strip/scrollback/command row, and between the individual
  # vital bars) -- those gaps have no widget of their own, so without this
  # the window's default GTK theme background (light gray in the common
  # case) shows through every one of them regardless of any other color
  # setting, reported live as visibly mismatched (2026-09-13). Named (and
  # grouped under config.yml's `global:` section, alongside padding itself)
  # for what it actually colors -- the padding gaps -- rather than the
  # `window_background` under its own `window:` section it briefly shipped
  # as, per the user's own later rename spec (2026-09-13). Originally
  # defaulted to game_window_bg so the whole window read as one consistent
  # color out of the box; since retuned, through the user's own live use,
  # to its own dark charcoal (#222222) one shade lighter than game_window_bg
  # -- close enough to still read as one window, distinct enough to show
  # the padding gaps have their own identity -- and promoted from their
  # config.yml as the new baseline default (2026-09-13, see padding/
  # title_bar_bg for the other two defaults promoted the same way).
  Theme = Data.define(
    :game_window_bg, :game_window_fg, :font_family, :font_size,
    :vitals_colors, :roundtime_hard, :roundtime_cast,
    :title_bar_bg, :title_bar_fg,
    :padding, :padding_bg, :border_color, :border_width,
    :vitals_border_color, :vitals_border_width, :vitals_fg, :indicator_fg,
    :command_bar_bg, :command_bar_fg, :command_bar_font_family, :command_bar_font_size,
    :roundtime_fg,
    :show_vitals_bar, :show_roundtime_bar, :show_status_bar
  )

  # Reopened as a plain class body (rather than continuing Data.define's own
  # block) so DEFAULT's constant assignment lands on Theme itself --
  # assigning a constant inside Data.define's block instead follows the
  # block's lexical scope (Grimoire), silently defining Grimoire::DEFAULT
  # rather than Grimoire::Theme::DEFAULT, confirmed while writing this.
  class Theme
    DEFAULT = new(
      game_window_bg: Color.new(red: 0, green: 0, blue: 0),
      game_window_fg: Color.new(red: 255, green: 255, blue: 255),
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
      roundtime_hard: Color.new(red: 200, green: 0, blue: 0),
      roundtime_cast: Color.new(red: 0, green: 0, blue: 200),
      title_bar_bg: Color.new(red: 26, green: 26, blue: 26),
      title_bar_fg: Color.new(red: 255, green: 255, blue: 255),
      padding: 2,
      padding_bg: Color.new(red: 34, green: 34, blue: 34),
      border_color: Color.new(red: 100, green: 100, blue: 100),
      border_width: 0,
      vitals_border_color: Color.new(red: 100, green: 100, blue: 100),
      vitals_border_width: 0,
      vitals_fg: Color.new(red: 255, green: 255, blue: 255),
      indicator_fg: Color.new(red: 255, green: 255, blue: 255),
      command_bar_bg: Color.new(red: 0, green: 0, blue: 0),
      command_bar_fg: Color.new(red: 255, green: 255, blue: 255),
      command_bar_font_family: 'Overpass Mono, monospace',
      command_bar_font_size: 11,
      roundtime_fg: Color.new(red: 255, green: 255, blue: 255),
      show_vitals_bar: true,
      show_roundtime_bar: true,
      show_status_bar: true
    )
  end
end
