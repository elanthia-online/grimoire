require_relative 'color'

module Grimoire
  # The full set of user-configurable appearance settings: the game window's
  # (scrollback/entry) background and text color, the scrollback font, the
  # command_vitals/roundtime-bar fill colors, the title bar colors, and the
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
  # DEFAULT's vitals_colors/command_vitals_colors/roundtime_hard/
  # roundtime_cast values are the same fixed constants the former
  # VitalsColors module carried (see docs/decisions.md's entry on that
  # module for the reasoning behind the per-field choices: red for health,
  # blue for mana, etc.) -- this class takes over that role now that a
  # settings file exists to override them, per TASKS.md's
  # "User-selectable/configurable vitals-strip colors" item. The two
  # hashes were one `vitals_colors` field (all 7) until 2026-09-15, split
  # once health/mana/stamina/spirit's only remaining consumer
  # (command_vital_css) was command_vitals specifically -- see
  # command_vitals_colors' own comment below.
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
  #   every one of its rows/gaps (scrollback, command row, the individual
  #   command_vitals bars, and the indicator block's own icon spacing) --
  #   its original role, unchanged. (Originally also covered the
  #   top-of-window vitals strip and its own bars/indicator-label gap;
  #   that widget was removed 2026-09-15 -- see docs/decisions.md.)
  # - As CSS content padding *inside* every bordered widget (the scrollback
  #   text, the command entry, and the fill within each command_vitals/
  #   roundtime progress bar's trough), so there is breathing room between a
  #   border and its own content too, not just between widgets. See
  #   Window#inset for how the command_vitals/roundtime bars keep their
  #   overall rendered size fixed (ICON_SIZE; ROUNDTIME_BAR_WIDTH/HEIGHT, the
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
  # command_vitals/roundtime bar's trough. Both border widths default to 0
  # (no visible border) so a config file only needs to set a width to opt
  # in. There is deliberately no vitals background field of any kind --
  # every progress bar's trough background is a fixed #000000 regardless of
  # any other color setting, the user's own spec (2026-09-13); see Window's
  # PROGRESS_BAR_BACKGROUND for where that constant actually lives.
  #
  # vitals_fg colors command_vitals's own overlaid current/max number text
  # (e.g. "351/355", see Window#build_command_vital_bar) -- previously not
  # configurable at all, left at whatever the system GTK theme's own
  # default progressbar-text color happened to be, the user's own spec
  # (2026-09-13, back when this colored the now-removed top-of-window
  # vitals strip's own per-bar label text -- see docs/decisions.md).
  # Defaults to white for contrast against the fixed #000000 progress-bar
  # background (see the PROGRESS_BAR_BACKGROUND note above). Unlike every
  # other font on this theme, this label's font *family* is deliberately
  # not a Theme field at all -- the user explicitly asked for it to switch
  # to plain Overpass (not the Mono variant used elsewhere) without being
  # made configurable; see Window::VITALS_FONT_FAMILY, a plain string
  # constant #command_vitals_text_css interpolates directly rather than
  # reading off @theme, the same pattern PROGRESS_BAR_BACKGROUND already
  # uses for a setting that is intentionally fixed rather than themeable.
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
  # show_roundtime_bar gates whether Window#build_roundtime_bar constructs
  # its widget at all, rather than building it and hiding the result -- per
  # BACKLOG.md's "Widget visibility toggles" item, config-file-only for now
  # (a restart is needed to pick up a change), not a live menu toggle.
  # Defaults true (today's always-on roundtime bar is unchanged). The
  # config.yml key is `command_bar.roundtime.enabled` as of 2026-09-15
  # (moved from a top-level `roundtime:` section, alongside every other
  # `show` key across config.yml being renamed to `enabled` the same day --
  # see Config#theme/ConfigTemplate for the full key layout); this field's
  # own Ruby name is unchanged.
  #
  # The old top-of-window vitals strip (a labeled health/mana/stamina/
  # spirit/mind/encumbrance/stance bar row plus a text-based active-
  # indicators label, e.g. "STUNNED BLEEDING") and its show_vitals_bar/
  # show_status_bar/indicator_fg toggles were removed outright on
  # 2026-09-15, the user's own spec, once the command_bar-based
  # equivalents (command_vitals's own bars, status_indicators' own icon
  # block) existed, defaulted on, and fully superseded it as the
  # out-of-the-box display -- both toggles had already been flipped to
  # *false* by default earlier that same day as an interim step before the
  # removal. vitals_fg/vitals_border_color/vitals_border_width remain:
  # command_vital_css (Window) still reads them for command_vitals's own
  # bar text/border styling (vitals_border_color/width also still shared
  # with the roundtime bar's own trough border -- see roundtime_css), just
  # with no top-level enable/disable toggle of their own any more --
  # command_vitals display is governed by show_command_vitals alone. See
  # docs/decisions.md for the removal writeup. The old strip's own
  # health/mana/stamina/spirit fill colors were moved out of vitals_colors
  # into their own command_vitals_colors field the same day, once
  # command_vital_css was confirmed to be their only remaining reader --
  # see that field's own comment.
  #
  # roundtime_min_rt is the number of remaining seconds (whichever of hard/
  # cast roundtime is greater) at which the roundtime bar reads "full" --
  # previously Window::ROUNDTIME_FULL_SECONDS, a fixed 10, made a Theme
  # field (and renamed min_rt in config.yml, under the same
  # `command_bar.roundtime` section) per the user's own spec (2026-09-15).
  # Defaults to 5 (down from the old fixed 10); Config itself clamps a
  # configured value below 3 up to 3 rather than rejecting it outright
  # (unlike every other numeric setting's min:, which raises) -- the user's
  # own spec, 2026-09-15. Theme itself carries no such clamp -- validation
  # lives in Config alone, the same split every other guarded field already
  # has (e.g. MAX_COMMAND_BAR_FONT_SIZE only applies through Config, not to
  # a Theme constructed directly).
  #
  # show_debug_menu gates Window#build_debug_panel, a live dump of
  # VitalsState's own fields (health/mana/.../stance/roundtime_end/
  # cast_roundtime_end/indicators) as a two-column variable/value table
  # docked to the right of the main layout -- a development/troubleshooting
  # aid, not a normal-play widget, so unlike the three toggles above this
  # one defaults to *false*.
  #
  # show_command_vitals gates Window#build_command_vitals -- a second,
  # compact health/mana/stamina/spirit bar row docked directly beneath the
  # command entry (see Window's own class comment on the command area
  # layout), the user's own spec (2026-09-15). command_vitals_show_numbers
  # only matters once this is true: whether each bar's own current/max
  # fraction (e.g. "351/355", Vital#text with its leading label word
  # stripped -- these bars carry no label of their own, per the user's own
  # spec: "no description or text") renders at all, always centered on the
  # bar (GtkProgressBar's own built-in show_text always centers with no
  # alignment control anyway -- see Window's own comment on why the
  # roundtime label already has to be a separate Gtk::Overlay label rather
  # than the bar's own text for the same reason, so these bars use that
  # same overlay-label technique instead of show_text). A left/center/right
  # justify option existed briefly (2026-09-15) but was removed the same
  # day, the user's own spec: centered only, no configurable alignment.
  #
  # config.yml keys are `command_bar.command_vitals.enabled`/`show_numbers`
  # as of 2026-09-15 (moved from a top-level `command_vitals:` section,
  # alongside roundtime/status_indicators making the same move the same
  # day -- see Config#theme/ConfigTemplate for the full key layout); these
  # fields' own Ruby names are unchanged. Both default *true* as of that
  # move too (show_command_vitals revised up from an initial *false* --
  # the "brand new, not existing UI" reasoning show_debug_menu still uses
  # -- command_vitals_show_numbers already defaulted true) -- the user's
  # own spec, 2026-09-15.
  #
  # command_vitals_colors (health/mana/stamina/spirit fill colors) lived in
  # the shared `vitals_colors` hash alongside mind/encumbrance/stance until
  # 2026-09-15, when the old top-of-window vitals strip that read all 7
  # fields was removed -- command_vital_css (Window) was left as the only
  # remaining reader of these particular 4, and it already only ever reads
  # command_vitals fields, so the user's own follow-up spec split them out
  # into their own field, nested under `command_bar.command_vitals.*` in
  # config.yml (siblings of `enabled`/`show_numbers`) rather than staying
  # under the top-level `vitals:` section. mind/encumbrance/stance stay in
  # `vitals_colors` under `vitals:` -- nothing reads them for display any
  # more (the debug panel shows their raw percent/text, not a themed
  # color), but nothing asked for them to be removed either, only moved.
  #
  # show_indicators gates Window#build_indicator_block -- the live,
  # icon-based 4-slot display driven by IndicatorGroups.slots (posture,
  # group, stealth, status). config.yml key is `command_bar.status_indicators.enabled` as of
  # 2026-09-15 (moved from a top-level `indicators:` section, this field's
  # own Ruby name unchanged), defaulting *true* -- the user's own later
  # spec that same day, revising an initial *false* default (the same
  # "brand new, not existing UI" reasoning show_debug_menu still uses;
  # show_command_vitals carried this same reasoning too until it was also
  # flipped to *true* the same day).
  #
  # status_indicators_location (config.yml key
  # `command_bar.status_indicators.location`, :left/:right, default
  # :left as of 2026-09-15, revised the same day from an initial :right)
  # governs both where the block sits *and* its own grid shape -- the
  # user's own spec (2026-09-15), reworking the original "always right of
  # command_stack" placement:
  #
  # - :right (the original, unchanged behavior): docked to the right of
  #   everything else in the command row. A single 4x1 row when
  #   show_command_vitals is off, or a 2x2 grid when it is on -- this
  #   grid-shape derivation is the same either way, not itself a Theme
  #   field.
  # - :left: only forced to a 4x1 row while show_roundtime_bar is also on
  #   -- that is the "left of"/"beneath the roundtime bar" placement
  #   below, which needs a fixed 4x1 shape either way (see
  #   Window#force_four_by_one?). With show_roundtime_bar off, :left has
  #   nothing to line up against, so it follows the same
  #   show_command_vitals-driven 2x2-or-4x1 shape :right always has --
  #   revised (2026-09-15) from an initial blanket "4x1 in all
  #   circumstances", the user's own correction reported live after the
  #   original spec shipped. Placement: with show_roundtime_bar on, docked
  #   to the left of the roundtime bar if show_command_vitals is off, or
  #   stacked directly beneath the roundtime bar (the same column,
  #   command_stack still to its right) if show_command_vitals is on --
  #   see Window#build_window's own comment for the height reconciliation
  #   the "beneath" case needs (the roundtime bar's own height shrinks
  #   back to plain #command_bar_height there, with the indicator row
  #   filling the rest of the column to still match command_stack's own
  #   height). With show_roundtime_bar off, :left just docks the block to
  #   the left of command_stack directly, nothing to be "left of" or
  #   "beneath" instead.
  #
  # padding_bg paints the Gtk::Window itself, which is what actually shows
  # through padding's own gaps (the outer border and the spacing between
  # scrollback/command row, and between the individual command_vitals
  # bars) -- those gaps have no widget of their own, so without this
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
    :vitals_colors, :command_vitals_colors, :roundtime_hard, :roundtime_cast,
    :title_bar_bg, :title_bar_fg,
    :padding, :padding_bg, :border_color, :border_width,
    :vitals_border_color, :vitals_border_width, :vitals_fg,
    :command_bar_bg, :command_bar_fg, :command_bar_font_family, :command_bar_font_size,
    :roundtime_fg, :roundtime_min_rt,
    :show_roundtime_bar, :show_debug_menu,
    :show_command_vitals, :command_vitals_show_numbers,
    :show_indicators, :status_indicators_location
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
        :mind        => Color.new(red: 128, green: 0,   blue: 200),
        :encumbrance => Color.new(red: 150, green: 150, blue: 150),
        :stance      => Color.new(red: 150, green: 150, blue: 150),
      }.freeze,
      command_vitals_colors: {
        :health  => Color.new(red: 200, green: 0,   blue: 0),
        :mana    => Color.new(red: 0,   green: 0,   blue: 200),
        :stamina => Color.new(red: 200, green: 160, blue: 0),
        :spirit  => Color.new(red: 200, green: 200, blue: 200),
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
      command_bar_bg: Color.new(red: 0, green: 0, blue: 0),
      command_bar_fg: Color.new(red: 255, green: 255, blue: 255),
      command_bar_font_family: 'Overpass Mono, monospace',
      command_bar_font_size: 11,
      roundtime_fg: Color.new(red: 255, green: 255, blue: 255),
      roundtime_min_rt: 5,
      show_roundtime_bar: true,
      show_debug_menu: false,
      show_command_vitals: true,
      command_vitals_show_numbers: true,
      show_indicators: true,
      status_indicators_location: :left
    )
  end
end
