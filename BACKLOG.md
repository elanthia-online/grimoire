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

