# Backlog

Post-MVP work: real, not urgent for the first working scrollback-and-input loop. See [TASKS.md](TASKS.md) for the active MVP list and [CLAUDE.md](CLAUDE.md) for ground rules. Items here move back into TASKS.md if they become blocking.

## Stream parsing

- [ ] Route non-narrative panel tags to structured state, not the main text pane — `room objs`/`room players` and `progressBar`/`indicator`/`roundTime`/`castTime` already made this migration (see TASKS.md's "Stream parsing" and "Structured room state"/"Structured vitals/status state" entries). Everything else is, as of 2026-09-13, a **temporary wholesale squelch, not real routing**: `lib/grimoire/panel_tag_tracker.rb` (`PanelTagTracker`) drops `dialogData`, `openDialog`, `roommeta`, `spell`, `left`, `right`, `resource`, `style`, `skin`, `image`, `pulse`, `label`, `compass` outright — confirmed necessary against a real live-captured session (see `docs/decisions.md`: 38 of 54 blank lines in a real parsed-output log traced to this, plus one garbled `spell`/`left`/`right` concatenation), not just the fixtures. `inv`'s container-listing shape (`spec/fixtures/inventory.xml` "Shape C") still leaks into narrative too and is not in `PanelTagTracker`'s list. Revisit `PanelTagTracker`'s remaining drop list item-by-item once a UI actually wants any of this (prepared-spell/hands) — see `docs/decisions.md` for the exact migration path `room objs`/`room players` and `progressBar`/`indicator`/`roundTime`/`castTime` already took.

## From ProfanityFE (2026-09-14)

Candidate features drawn from ProfanityFE's `USER_GUIDE.md`, cross-checked against what grimoire's MVP already ships (see TASKS.md). Per CLAUDE.md's licensing section, ProfanityFE is GPLv2 and grimoire is MIT: these describe *behavior* to reimplement independently, not code, XML schema, or structure to copy. Unsorted/unprioritized — pull individual items into TASKS.md as they're picked up.

### Display/output text processing

- [ ] Highlight system — regex-based fg/bg/underline rules applied to scrollback text, config-defined, reloadable
- [ ] Gag patterns — general (all streams), combat-specific, and multi-line block (start/end, prompt-terminated fallback, safety cap) line suppression
- [ ] Perc-transform-equivalent — user-defined regex substitutions to shorten effect/spell display text

### Multi-pane layout

- [ ] Configurable multi-window layout (text/tabbed/indicator/progress/countdown/room/exp/perc/sink-style panes), sized via terminal/window-relative expressions, superseding today's single scrollback pane
- [ ] Stream routing config — map protocol streams (combat, assess, thoughts, lnet, voln, death, logons, familiar, ooc, atmospherics, moonWindow, shopWindow) to specific panes or a sink, instead of the current blanket squelch in `panel_tag_tracker.rb`
- [ ] Tabbed window — multiple stream buffers in one pane, tab bar, unread-activity marker, per-tab scroll position
- [ ] Room window — UI consumer for the already-tracked `room_state.rb`/`room_tracker.rb` data (title/desc/objects/players/exits/room number), with creature highlighting
- [ ] Experience/skills window — live skill list (rank/percent/mindstate), colorable via the highlight system
- [ ] Active-effects (perc) window — spells/effects sorted by remaining duration, with an abbreviation lookup table
- [ ] Compass/hand/spell/status indicator widgets — compass directions, hand contents, prepared spell, boolean status (stunned/bleeding/kneeling/prone/sitting/hidden/dead/joined/webbed), per-body-part injury levels
- [ ] Arbitrary/custom progress bars — let scripts push a named progress bar (id/max/current/label/colors) that reuses a configured progress widget
- [ ] Generalized countdown bars beyond roundtime (e.g. stun countdown), reusing the same countdown-widget concept as the existing roundtime bar

### Interaction/runtime

- [ ] Hot-reload of highlights/gags/keybinds/perc-transforms without restart
- [ ] Runtime layout switching between named layouts
- [ ] Key binding / macro configuration — user-definable key-to-action and key-to-macro mapping in config, including multi-key combos
- [ ] Dot-command layer — local commands not sent to the game (quit, reload, layout switch, resize, tab management, arrow-mode cycling, links/selection toggles, inline highlight add/remove, help), unrecognized `.` input passed through to Lich as `;`
- [ ] Scrollback navigation — page/line scroll, jump-to-bottom, active/inactive scroll indicator, auto-scroll pause while reading history, per-pane buffer size cap
- [ ] Clickable in-game links — parse link tags, highlight, click-to-send
- [ ] Mouse text selection — drag-to-select, double/triple-click word/line select, clipboard copy
- [ ] Command-line autocomplete from command history
- [ ] Command history refinements — minimum-length filter before saving, consecutive-duplicate suppression, kill-ring style cut/paste

### Housekeeping/ops

- [ ] Window/process title updates showing character name and room/prompt state, toggleable
- [ ] Multi-character support — per-character config resolution and separate log files for concurrent instances (the `--character NAME` flag now exists for session discovery — see CLAUDE.md's "Connection model" — this item can key off the same name for config/log-dir resolution instead of inventing its own)
- [ ] Settings cache for fast startup, auto-invalidated on config file change
- [ ] Optional boot/perf profiling flag logging a startup timing breakdown

## Standalone / multi-character mode (2026-09-15)

Turns grimoire from "point it at one already-running Lich session" into a
standalone shell: starts blank, can list and attach to already-running Lich
sessions, can launch new `--headless` Lich processes itself from a saved
character list, manages several character connections at once behind a
switchable sidebar, supports a two-up split view, and lets theme config show/
hide individual widgets. Does **not** revisit CLAUDE.md's "Connection model"
decision -- grimoire still never performs its own EAS auth, it still only
ever talks to Lich's frontend socket; this only changes how many of those it
can hold open at once and who triggers the `lich --headless` launch. Real,
substantial, and cuts across most of the app -- outline only, unprioritized,
pull pieces into TASKS.md individually as they're picked up.

### Shell & connection menu

- [ ] Blank-start shell window with a menu bar, no character connection
      required at launch -- today's `App#run` assumes host/port are already
      known (from `--host`/`--port` or `--character`) and connects
      immediately; a no-args launch mode needs to skip straight to `Gtk.main`
      with nothing connected yet
- [ ] Menu action: list open connections, reusing `SessionLocator.list` as-is
      (already enumerates every `*.session` file, valid or not, with no live
      connection needed)
- [ ] Menu action: attach to a listed session -- opens a new per-character
      view (see "Sidebar" below) using that session's host/port, same
      `Connection`/`NarrativeStream` wiring `App` already does for one

### Lich headless launch

- [ ] Saved-character store (new config, separate from `config.yml`'s theme
      settings -- name at minimum; decide whether login/auth beyond the
      character name needs to live here at all, since Lich itself owns EAS)
- [ ] Launch action: spawn `lich --login <name> --detachable-client=auto
      --headless` (confirm exact headless flag/behavior against lich-5
      source before relying on it, same "confirm against source, do not
      assume" discipline CLAUDE.md's connection-model section already used
      for `SET_FRONTEND_PID`)
- [ ] Process lifecycle tracking: child PID, stdout/stderr capture or
      redirect, crash/exit detection, a way to stop/restart from the UI
- [ ] Startup race handling for the launch case specifically -- reuse
      `SessionLocator`'s existing retry loop (`DEFAULT_RETRIES`/
      `DEFAULT_RETRY_INTERVAL`), but the launch path also needs to decide
      what happens to the spawned Lich process if grimoire itself exits or
      crashes first (left running headless for later reattachment, or
      killed with it) -- open question, resolve when this is picked up

### Sidebar & multi-session view switching

- [ ] Extract today's single-session stack (`Connection`, `CommandQueue`,
      `NarrativeStream`, `SessionLogger`, plus the tracker chain feeding
      `NarrativeStream`) out of `App` into a per-character session object,
      so `App`/its replacement can hold N of them instead of exactly one --
      `App#tick_roundtime`'s `GLib::Timeout` and every `GLib::Idle.add`
      marshal in `handle_line`/`display` are currently written assuming a
      single `@window`, they need to become per-session
- [ ] Dynamic left sidebar listing every open session (attached or
      launched); clicking one shows that character's current `Window`-
      equivalent view
- [ ] Background sessions keep running (socket read loop, command queue,
      vitals/room state) while not the visible one -- confirms the
      per-session extraction above needs to be fully independent of
      whether its view is currently on-screen
- [ ] Widget/container architecture decision needed here: does each
      character's view stay its own top-level `Gtk::Window` (multi-window),
      or does `Window`'s content become an embeddable widget swapped into a
      single shell window's content area (`Gtk::Stack` + sidebar, GTK's own
      `Gtk::StackSidebar` shape)? The split-view requirement below needs the
      same content widget to be reparentable into either a single pane or
      one side of a `Gtk::Paned`, which favors the embeddable-widget
      approach over separate top-level windows -- flag as the first design
      call to make when this section is picked up

### Split view

- [ ] Two-up `Gtk::Paned` (left|right) mode showing two sessions' views at
      once, independent of the sidebar's single-selection switch
- [ ] Depends on the "embeddable widget, not top-level window" call above --
      a GTK widget has exactly one parent at a time, so showing a session in
      a split pane means removing it from the sidebar-driven `Gtk::Stack`
      first, not literally showing it twice

### Widget visibility toggles

- [ ] New boolean `Theme` fields (e.g. `show_vitals_bar`, `show_roundtime_bar`,
      `show_status_bar`) alongside the existing color/font fields in
      `lib/grimoire/theme.rb`, surfaced in `config.yml`/`config_template.rb`
      the same way every other `Theme` field already is
- [ ] `Window`'s build methods (`build_vitals_strip`, the roundtime-bar
      overlay, the active-indicators label) conditionally skip construction
      instead of always packing every widget
- [ ] Open question to resolve when picked up: config-file-only (restart to
      change) vs. a live menu toggle -- the user's phrasing ("turn on/off...
      in themes") reads as config-driven, but a live toggle is a small
      extra step once the boolean fields exist and would fit naturally on
      the same menu bar as the connection-management actions above

