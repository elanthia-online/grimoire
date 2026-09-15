require_relative 'theme'

module Grimoire
  # Renders a full configs/config.yml-shaped YAML document from a Theme --
  # the single source of the key layout a human-edited config.yml carries,
  # so it never has to be hand-duplicated between two files. Per-key
  # descriptions live in docs/configuration.md, not inline here -- see that
  # file for the full settings reference (every key, type, default,
  # description) and lib/grimoire/theme.rb's Theme::DEFAULT for the
  # underlying values. Two callers:
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
        # ~/.config/grimoire/config.yml) on first run; edit whatever you want
        # to change -- a removed key reverts to its built-in default the next
        # time this file is rewritten. Full reference (every key, type,
        # default, description): docs/configuration.md. Colors are "#rrggbb"
        # hex strings; fg = foreground (text color), bg = background.

        theme:
          global:
            padding: #{theme.padding}
            padding_bg: '#{theme.padding_bg.to_hex}'

          title_bar:
            bg: '#{theme.title_bar_bg.to_hex}'
            fg: '#{theme.title_bar_fg.to_hex}'

          game_window:
            bg: '#{theme.game_window_bg.to_hex}'
            fg: '#{theme.game_window_fg.to_hex}'
            border:
              color: '#{theme.border_color.to_hex}'
              width: #{theme.border_width}

          font:
            family: '#{theme.font_family}'
            size: #{theme.font_size}

          command_bar:
            bg: '#{theme.command_bar_bg.to_hex}'
            fg: '#{theme.command_bar_fg.to_hex}'
            font:
              family: '#{theme.command_bar_font_family}'
              size: #{theme.command_bar_font_size}
            roundtime:
              hard: '#{theme.roundtime_hard.to_hex}'
              cast: '#{theme.roundtime_cast.to_hex}'
              fg: '#{theme.roundtime_fg.to_hex}'
              enabled: #{theme.show_roundtime_bar}
              min_rt: #{theme.roundtime_min_rt}
            status_indicators:
              enabled: #{theme.show_indicators}
              location: '#{theme.status_indicators_location}'
            command_vitals:
              enabled: #{theme.show_command_vitals}
              show_numbers: #{theme.command_vitals_show_numbers}
              health: '#{theme.command_vitals_colors[:health].to_hex}'
              mana: '#{theme.command_vitals_colors[:mana].to_hex}'
              stamina: '#{theme.command_vitals_colors[:stamina].to_hex}'
              spirit: '#{theme.command_vitals_colors[:spirit].to_hex}'

          vitals:
            mind: '#{theme.vitals_colors[:mind].to_hex}'
            encumbrance: '#{theme.vitals_colors[:encumbrance].to_hex}'
            stance: '#{theme.vitals_colors[:stance].to_hex}'
            fg: '#{theme.vitals_fg.to_hex}'
            border:
              color: '#{theme.vitals_border_color.to_hex}'
              width: #{theme.vitals_border_width}

          debug:
            enabled: #{theme.show_debug_menu}
      YAML
    end
  end
end
