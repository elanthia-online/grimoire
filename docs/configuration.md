# Configuration reference

Grimoire's appearance is controlled by a YAML settings file, auto-created the
first time grimoire runs.

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
- `show`/`indicator_show` keys are plain YAML booleans (`true`/`false`),
  read only at startup -- changing one needs a restart to take effect.

## Settings

| Key | Type | Default | Description |
|---|---|---|---|
| `global.padding` | integer (px) | `2` | Applied twice: as the outer window margin and the spacing between every row/gap in the layout (vitals strip, scrollback, command row, individual vital bars), and as CSS content padding inside every bordered widget (scrollback text, command entry, vitals/roundtime bar fill) so there is breathing room between a border and its own content too. |
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
| `command_bar.font.size` | integer (pt) | `11` | Command entry font size. |
| `vitals.health` | color | `#c80000` | Health bar fill color. |
| `vitals.mana` | color | `#0000c8` | Mana bar fill color. |
| `vitals.stamina` | color | `#c8a000` | Stamina bar fill color. |
| `vitals.spirit` | color | `#c8c8c8` | Spirit bar fill color. |
| `vitals.mind` | color | `#8000c8` | Mind bar fill color. |
| `vitals.encumbrance` | color | `#969696` | Encumbrance bar fill color. |
| `vitals.stance` | color | `#969696` | Stance bar fill color. |
| `vitals.fg` | color | `#ffffff` | Per-bar label text color (e.g. "Health 253/355"). |
| `vitals.indicator_fg` | color | `#ffffff` | Active-status-indicator label color (e.g. "STUNNED BLEEDING"), independent of `vitals.fg`. |
| `vitals.border.color` | color | `#646464` | Border color shared by every vitals-strip/roundtime bar's trough. |
| `vitals.border.width` | integer (px) | `0` | Border width shared by every vitals-strip/roundtime bar's trough. `0` = no visible border. |
| `vitals.show` | boolean | `true` | Whether the health/mana/stamina/spirit/mind/encumbrance/stance bars are built at all. `false` removes the row entirely, independent of `vitals.indicator_show`. |
| `vitals.indicator_show` | boolean | `true` | Whether the active-status-indicator label (e.g. "STUNNED BLEEDING") is built at all, independent of `vitals.show`. |
| `roundtime.hard` | color | `#c80000` | Roundtime bar fill color while hard roundtime (most actions) is running. |
| `roundtime.cast` | color | `#0000c8` | Roundtime bar fill color once hard roundtime has ended but cast roundtime (spell preparation) continues. |
| `roundtime.fg` | color | `#ffffff` | Roundtime bar's overlaid "RT: n" text color. |
| `roundtime.show` | boolean | `true` | Whether the roundtime bar (next to the command entry) is built at all. |

## Fixed (not configurable)

A few style values are deliberately not exposed as settings:

- Every progress bar's trough background (vitals strip and roundtime bar
  alike) is fixed at `#000000` regardless of any other color setting.
- The vitals-strip label's font *family* is fixed at plain Overpass (not the
  Mono variant used elsewhere) -- only its color (`vitals.fg`) is
  configurable.
- The roundtime bar's "RT: n" text is always bold; only its color
  (`roundtime.fg`) is configurable.
