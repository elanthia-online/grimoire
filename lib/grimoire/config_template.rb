require_relative 'theme'

module Grimoire
  # Renders a full, commented configs/config.yml-shaped YAML document from a
  # Theme -- the single source of the key layout and prose explanations a
  # human-edited config.yml carries, so it never has to be hand-duplicated
  # between two files. Two callers:
  #
  # - Config.ensure_defaults_file! renders configs/defaults.yml from
  #   Theme::DEFAULT whenever that file is missing (see its own comment for
  #   why "missing" rather than "every run").
  # - Config#migrate! renders a user's own config.yml back onto itself from
  #   its own already-merged Theme (Theme::DEFAULT overridden field-by-field
  #   by whatever that file actually set -- see Config#theme) whenever a
  #   newer grimoire version has added a settings key that file predates.
  #   Because the input Theme already carries the user's own values for
  #   every key they *did* set, this "full rewrite" only ever changes the
  #   keys that were actually missing -- a safe upgrade path per the user's
  #   own spec (2026-09-13), at the cost of not preserving any hand-added
  #   comments/formatting in that file, which the user accepted.
  module ConfigTemplate
    def self.render(theme)
      <<~YAML
        # Grimoire settings file. Auto-created at configs/config.yml (or
        # ~/.config/grimoire/config.yml) on first run from configs/defaults.yml,
        # and edit whatever you want to change -- any key you remove reverts to
        # its built-in default (see lib/grimoire/theme.rb's Theme::DEFAULT) the
        # next time this file is rewritten, rather than failing to load. Colors
        # are "#rrggbb" hex strings. --config PATH on the command line overrides
        # both lookup locations. If a future grimoire version adds a settings
        # key this file predates, it is filled in here (with its default value)
        # the next time grimoire runs -- every other key you already set is left
        # untouched.
        #
        # Abbreviations used below: `fg` = foreground (text color), `bg` = background.

        theme:
          # Settings that apply across every widget rather than to one specific
          # one. padding (px) is applied twice over: as the outer window margin
          # and the spacing between every row/gap in the layout (the vitals
          # strip, scrollback, command row, the individual vital bars, and the
          # gap above the indicator line), and as CSS content padding *inside*
          # every bordered widget below (scrollback text, the command entry,
          # and the fill within each vitals-strip/roundtime bar's trough), so
          # there is breathing room between a border and its own content too.
          # padding_bg is what actually shows through those padding gaps (the
          # gaps themselves have no widget of their own to paint `game_window`'s
          # own bg onto).
          global:
            padding: #{theme.padding}
            padding_bg: '#{theme.padding_bg.to_hex}'

          # The window's title bar (a custom Gtk::HeaderBar grimoire supplies
          # itself -- a native, window-manager-drawn title bar is not a themeable
          # GTK widget).
          title_bar:
            bg: '#{theme.title_bar_bg.to_hex}'
            fg: '#{theme.title_bar_fg.to_hex}'

          # The game window -- the primary scrollback output pane, as distinct
          # from the command entry below (`command_bar`) and grimoire's own
          # top-level window chrome (`global.padding_bg` above, `title_bar`
          # above).
          game_window:
            bg: '#{theme.game_window_bg.to_hex}'
            fg: '#{theme.game_window_fg.to_hex}'

            # Optional border frame around the scrollback/command-entry widgets
            # -- shared between the two, unlike bg/fg/font below.
            # width defaults to 0 (no visible border) -- set it to opt in.
            border:
              color: '#{theme.border_color.to_hex}'
              width: #{theme.border_width}

          # Font used for the scrollback text. `family` is passed straight through
          # as a CSS font-family value (not wrapped in quotes for you), so it can
          # be a single name ('Monospace' -- Pango's own generic alias) or a full
          # fallback list, as below: a specific font first, then a generic family
          # so the display still comes out monospaced even on a system that lacks
          # the specific one. This is the built-in default (Theme::DEFAULT) --
          # Overpass Mono ships as a bundled font under assets/fonts/ (see that
          # directory's README), loaded without needing a system-wide install.
          font:
            family: '#{theme.font_family}'
            size: #{theme.font_size}

          # The command entry (where you type commands) -- independent of
          # `game_window` above, with its own bg/fg/font (border/padding still
          # come from `game_window.border`/`global.padding`, shared between the
          # two). Defaults to the same colors/font as `game_window`/`font`
          # above so the default look is unchanged.
          command_bar:
            bg: '#{theme.command_bar_bg.to_hex}'
            fg: '#{theme.command_bar_fg.to_hex}'
            font:
              family: '#{theme.command_bar_font_family}'
              size: #{theme.command_bar_font_size}

          # Vitals-strip bar fill colors, one per tracked field. There is no
          # `bg` key here -- every progress bar's trough background (vitals
          # strip and roundtime bar alike) is a fixed #000000 regardless of any
          # other color setting, not configurable. `fg` is the label text color
          # (e.g. "Health 253/355"). The label's font *family* is likewise not
          # configurable -- it is always plain Overpass (not the Mono variant
          # used elsewhere), the user's own spec (2026-09-13).
          vitals:
            health: '#{theme.vitals_colors[:health].to_hex}'
            mana: '#{theme.vitals_colors[:mana].to_hex}'
            stamina: '#{theme.vitals_colors[:stamina].to_hex}'
            spirit: '#{theme.vitals_colors[:spirit].to_hex}'
            mind: '#{theme.vitals_colors[:mind].to_hex}'
            encumbrance: '#{theme.vitals_colors[:encumbrance].to_hex}'
            stance: '#{theme.vitals_colors[:stance].to_hex}'
            fg: '#{theme.vitals_fg.to_hex}'

            # Optional border frame around each vitals-strip/roundtime bar's
            # trough. width defaults to 0 (no visible border) -- set it to opt in.
            border:
              color: '#{theme.vitals_border_color.to_hex}'
              width: #{theme.vitals_border_width}

          # Roundtime bar fill colors -- hard roundtime (most actions) and cast
          # roundtime (spell preparation); see TASKS.md's "Basic vitals/indicator
          # area" entry for how the two combine into one displayed bar.
          roundtime:
            hard: '#{theme.roundtime_hard.to_hex}'
            cast: '#{theme.roundtime_cast.to_hex}'
      YAML
    end
  end
end
