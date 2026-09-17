# Configuration reference

Grimoire's appearance, and where to find the Lich install it launches sessions from, are controlled by a YAML settings file, auto-created the first time grimoire runs.

## File locations

The first of these that already exists on disk is used:

1. `configs/config.yml` (relative to the working directory)
2. `~/.config/grimoire/config.yml`

`--config PATH` on the command line overrides both lookup locations. If
neither exists yet, grimoire creates `configs/config.yml` from
`configs/defaults.yml` (itself auto-regenerated from the built-in defaults on
every run -- see `Grimoire::Theme::DEFAULT` in `lib/grimoire/theme.rb`).

Remove a key to revert it to its built-in default the next time the file is
rewritten, rather than failing to load. If a newer grimoire version adds a
settings key an existing file predates, that key is filled in (at its
default value) the next time grimoire runs -- every key already set is left
untouched.

## Format

- Colors are `"#rrggbb"` hex strings.
- `fg` = foreground (text color), `bg` = background.
- `family`/`size` under a `font:` block set a CSS `font-family`/point size.
- `enabled`/`show_numbers` keys are plain YAML booleans (`true`/`false`),
  read only at startup -- changing one needs a restart to take effect.
  Every plain `show` key in this file was renamed `enabled` on 2026-09-15;
  `show_numbers` is unchanged (it was never literally `show`).

## Settings

| Key | Type | Default | Description |
|---|---|---|---|
| `global.padding` | integer (px) | `2` | Applied twice: as the outer window margin and the spacing between every row/gap in the layout (scrollback, command row, individual command_vitals bars), and as CSS content padding inside every bordered widget (scrollback text, command entry, command_vitals/roundtime bar fill) so there is breathing room between a border and its own content too. |
| `global.padding_bg` | color | `#222222` | Background of the top-level window, which is what actually shows through `padding`'s own gaps (they have no widget of their own). |
| `title_bar.bg` | color | `#1a1a1a` | Background of the custom title bar. Grimoire supplies its own `Gtk::HeaderBar` since a native, window-manager-drawn title bar is not a themeable GTK widget. |
| `title_bar.fg` | color | `#ffffff` | Title bar text color. |
| `game_window.bg` | color | `#000000` | Scrollback output pane background. |
| `game_window.fg` | color | `#ffffff` | Scrollback output pane text color. |
| `game_window.border.color` | color | `#646464` | Border color shared by the scrollback pane and the command entry. |
| `game_window.border.width` | integer (px) | `0` | Border width shared by the scrollback pane and the command entry. `0` = no visible border. |
| `font.family` | string (CSS `font-family`) | `'Overpass Mono, monospace'` | Scrollback text font. A single name (e.g. `'Monospace'`) or a fallback list (specific font first, then a generic family). Overpass Mono ships bundled under `assets/fonts/` (see that directory's README), no system-wide install needed. |
| `font.size` | integer (pt) | `11` | Scrollback text font size. |
| `command_bar.bg` | color | `#000000` | Command entry background -- independent of `game_window`. |
| `command_bar.fg` | color | `#ffffff` | Command entry text color. |
| `command_bar.font.family` | string (CSS `font-family`) | `'Overpass Mono, monospace'` | Command entry font. Independent of `font.family`. |
| `command_bar.font.size` | integer (pt), max `16` | `11` | Command entry font size. Capped at 16pt: the entry's own height is pinned to a 32px floor GTK3's CSS itself cannot cap from above (there is no `max-height` property), so the font is capped instead of letting a large size grow the entry past it. |
| `command_bar.roundtime.hard` | color | `#c80000` | Roundtime bar fill color while hard roundtime (most actions) is running. |
| `command_bar.roundtime.cast` | color | `#0000c8` | Roundtime bar fill color once hard roundtime has ended but cast roundtime (spell preparation) continues. |
| `command_bar.roundtime.fg` | color | `#ffffff` | Roundtime bar's overlaid "RT: n" text color. |
| `command_bar.roundtime.enabled` | boolean | `true` | Whether the roundtime bar (next to the command entry) is built at all. |
| `command_bar.roundtime.min_rt` | integer (sec), floor `3` | `5` | Remaining seconds (whichever of hard/cast roundtime is greater) at which the bar reads "full". A configured value below 3 is silently raised to 3 rather than rejected. |
| `command_bar.status_indicators.enabled` | boolean | `true` | Whether a live, icon-based 4-slot indicator display (posture, group, stealth, status -- see `Grimoire::IndicatorGroups`) is built at all. Each icon is 32px. |
| `command_bar.status_indicators.location` | string (`left`/`right`) | `'left'` | Where the block sits, and its own grid shape. `right`: docked to the right of everything else in the command row; a single 4x1 row when `command_bar.command_vitals.enabled` is `false`, or a 2x2 grid (top: stealth/status, bottom: posture/group) when it is `true`. `left`, with the roundtime bar on: docked to the left of it when `command_vitals` is off (4x1), or stacked directly beneath it (same column, `command_vitals` still to its right, still 4x1) when `command_vitals` is on -- the roundtime bar's own height shrinks to make room, so the column still matches the command area's total height. `left`, with the roundtime bar off: nothing to line up 4x1 against, so it docks to the left of the command entry/`command_vitals` directly and follows the same `command_vitals`-driven 4x1-or-2x2 shape `right` always has. |
| `command_bar.command_vitals.enabled` | boolean | `true` | Whether a compact health/mana/stamina/spirit bar row is built beneath the command entry. These bars carry no label text, are 32px tall (matching the command entry and indicator icons), and the roundtime bar grows taller to span the entry plus this row once it is on. Fill colors come from `command_bar.command_vitals.*`; text color from `vitals.fg`. |
| `command_bar.command_vitals.show_numbers` | boolean | `true` | Whether each command_vitals bar shows its current/max number (e.g. "351/355") overlaid on the bar, always centered (not configurable). Only matters when `command_bar.command_vitals.enabled` is `true`. |
| `command_bar.command_vitals.health` | color | `#c80000` | Health bar fill color. |
| `command_bar.command_vitals.mana` | color | `#0000c8` | Mana bar fill color. |
| `command_bar.command_vitals.stamina` | color | `#c8a000` | Stamina bar fill color. |
| `command_bar.command_vitals.spirit` | color | `#c8c8c8` | Spirit bar fill color. |
| `vitals.mind` | color | `#8000c8` | Mind fill color. Not currently rendered by any widget (tracked in `VitalsState` but no longer displayed since the top-of-window vitals strip was removed) -- kept for a future display, not dead in the tracking sense. |
| `vitals.encumbrance` | color | `#969696` | Encumbrance fill color. Same status as `vitals.mind`. |
| `vitals.stance` | color | `#969696` | Stance fill color. Same status as `vitals.mind`. |
| `vitals.fg` | color | `#ffffff` | `command_bar.command_vitals`'s overlaid current/max number text color (e.g. "351/355"). |
| `vitals.border.color` | color | `#646464` | Border color shared by every command_vitals/roundtime bar's trough. |
| `vitals.border.width` | integer (px) | `0` | Border width shared by every command_vitals/roundtime bar's trough. `0` = no visible border. |
| `debug.enabled` | boolean | `false` | Whether a debug panel is docked to the right of the main layout: a live two-column (variable/value) dump of every `VitalsState` field, for troubleshooting -- not a themed gameplay widget, unlike every other setting on this page. |

## Lich install

A top-level `lich:` section, beside `theme:` rather than inside it, since it does not affect appearance. The table's keys are written in full here.

| Key | Type | Default | Description |
|---|---|---|---|
| `lich.dir` | string (path) | unset | The lich-5 install to launch headless sessions from: the directory holding `lich.rbw`. `~` is expanded. Launching is unavailable while unset. The path must also contain `data/entry.yaml` (Lich's saved logins), which grimoire reads for the list of favorites and never writes to; passwords in it are never read. A Lich started with `--home` to keep its data elsewhere is not supported yet. |

## Fixed (not configurable)

A few style values are deliberately not exposed as settings:

- Every progress bar's trough background (command_vitals and roundtime bar
  alike) is fixed at `#000000` regardless of any other color setting.
- `command_bar.command_vitals`'s overlaid number label font *family* is
  fixed at plain Overpass (not the Mono variant used elsewhere) -- only its
  color (`vitals.fg`) is configurable.
- The roundtime bar's "RT: n" text is always bold; only its color
  (`command_bar.roundtime.fg`) is configurable.
- The roundtime bar's own minimum width is fixed at four icon-widths (128px)
  plus the three inter-icon padding gaps a real 4x1
  `command_bar.status_indicators` row would have, so it exactly matches that
  row's own rendered width (still scaling with `global.padding`) regardless
  of `command_bar.status_indicators.location` -- not itself a setting.
