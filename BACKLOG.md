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
- [ ] Multi-character support — superseded by the "Standalone / multi-character mode" section below, which now specs both halves of this concretely: per-character config resolution under "Per-character display configuration", separate log files under "Tab bar & multi-session view switching" (`SessionLogger` keyed by character name instead of port)
- [ ] Settings cache for fast startup, auto-invalidated on config file change
- [ ] Optional boot/perf profiling flag logging a startup timing breakdown

## Standalone / multi-character mode (2026-09-15)

Turns grimoire from "point it at one already-running Lich session" into a
standalone shell: starts blank, can search for and attach to already-running
Lich sessions, can launch new `--headless` Lich processes itself from a saved
character list, manages several character connections at once behind a
GNOME-Terminal-style top tab bar, supports a two-up split view, and lets both
shell chrome and each character's display be themed independently. Does
**not** revisit CLAUDE.md's "Connection model" decision -- grimoire still
never performs its own EAS auth, it still only ever talks to Lich's frontend
socket; this only changes how many of those it can hold open at once and who
triggers the `lich --headless` launch. Real, substantial, and cuts across
most of the app -- outline only, unprioritized, pull pieces into TASKS.md
individually as they're picked up.

### Shell & connection menu

Picked up (2026-09-15): the blank-start shell itself and the `--character`/
`--port` pre-attach behavior moved to TASKS.md's "Multi-session shell
(standalone mode, phase 1)" section. The menu action below is not yet picked
up -- it needs the shell/tab bar from that section to exist first.

- [ ] Menu action: Connect -- one unified dialog (user's own call,
      2026-09-15, superseding the earlier separate "search/connect" and
      "attempt headless launch" items), listing every favorite from Lich's
      own `entry.yaml` (see "Lich headless launch" below), cross-checked
      against `SessionLocator.list` to show which are already running.
      Selecting an already-running favorite attaches directly (a new
      `Session` -- see `lib/grimoire/session.rb` -- pointed at that
      session file's host/port, same as the one `App` already builds).
      Selecting one that is not running triggers the headless launch below
      first, then attaches once its session file appears via the same
      startup-race retry loop `--character` discovery already uses.

### Lich headless launch

Simplified (user's own call, 2026-09-15): restrict launching to characters
Lich itself already has saved, rather than grimoire inventing its own
separate saved-character concept. Confirmed against current lich-5 source
(`lib/common/authentication/entry_store.rb`, `lich.rbw:12`):

- [ ] Lich directory location -- a new grimoire config setting (path to the
      lich-5 install, i.e. wherever `lich.rbw` lives) saved once and
      confirmed on every startup: verify `lich.rbw` and `data/entry.yaml`
      both exist under it before offering the Connect dialog's launch option
      at all, with a clear error/reconfigure prompt if not. Assumes the
      common case where `--home` was never used to relocate `LICH_DIR` away
      from `lich.rbw`'s own directory (`lich.rbw`'s own `--home=` handling,
      line 12) -- a lich install using `--home` to point elsewhere is a
      known gap, not solved here.
- [ ] Read Lich's own `<lich_dir>/data/entry.yaml` directly for the launch
      list, filtered to `is_favorite: true` entries, instead of a separate
      grimoire-side saved-character store -- `entry.yaml`'s own schema
      already carries `char_name`/`is_favorite`/`favorite_order`/`user_id`
      per character (`EntryStore.convert_yaml_to_legacy_format`).
      **Read-only** (user's own call, 2026-09-15): grimoire never writes to
      `entry.yaml`. Reads `char_name`, `is_favorite`, and `user_id` --
      `user_id` needed as an account-grouping key for the same-account
      collision guard below, never displayed or transmitted anywhere, still
      strictly distinct from `password`, which grimoire never reads at all
      -- keeping the "Lich owns all auth" boundary intact. Marking/unmarking
      a favorite stays a Lich-GUI-only action.
- [ ] Same-account collision guard (2026-09-15): GemStone/DragonRealms
      accounts only allow one logged-in character at a time, so launching a
      favorite whose account (`user_id`) already has a different character
      active would force-close that other session server-side. Before
      launching, group `entry.yaml`'s entries by `user_id`, then check
      `SessionLocator.list` for any sibling character (same `user_id`,
      different `char_name`) that currently has a valid session file. If
      found: warn, naming the sibling character and account, with an
      explicit "launch anyway" override rather than a silent proceed (user's
      own call, 2026-09-15) -- covers the case where switching characters on
      the same account is exactly what was intended. **Known gap:** this can
      only see sessions discoverable via `SessionLocator.list` (i.e.
      launched with `--detachable-client`, session file still present) -- a
      sibling character logged in through a different frontend entirely, or
      via Lich without a session file, is invisible to this check and stays
      unprotected.
- [ ] Launch action: spawn `lich --login <char_name> --headless=<port>` --
      confirmed as one combined, valid flag against lich-5 source
      (`lib/main/arg_normalization.rb`: `--headless[=PORT]` normalizes to
      `--without-frontend --detachable-client=PORT` on its own; a *separate*
      `--detachable-client` flag alongside it is what raises `ArgumentError`,
      not `--headless=PORT` itself, correcting this backlog's earlier
      version of this item). Port assigned sequentially by grimoire itself
      (default base `8000`, incrementing per concurrently-launched session;
      base configurable) rather than relying on `--headless=auto`'s
      OS-assigned port -- the user's own call, 2026-09-15.
- [ ] Precondition, not a grimoire-side fix: `SagaManagedLogin.cli_decision`
      (lich-5) passes any headless login straight through to Lich's existing
      auth path (`return decision(:passthrough) if headless`), not through
      Saga's interactive/managed login. A headless launch is therefore only
      non-interactive for a character that already has a saved login in
      Lich's own store -- consistent with restricting the launch list to
      `is_favorite: true` entries above, since every one of those already
      has a saved login by construction. A failed launch should still
      surface Lich's own error rather than grimoire trying to detect or work
      around it itself.
- [ ] Process lifecycle tracking: child PID, stdout/stderr capture or
      redirect, crash/exit detection, a way to stop/restart from the UI
- [ ] Per-character close-behavior setting (user's own call, 2026-09-15):
      "leave running" vs "send `quit`" -- `quit` is the actual GemStone/
      DragonRealms logout command, sent through the normal command path
      (`CommandQueue`, same as anything the character types), not a process
      signal or kill. Deliberately per character, not global (e.g.
      character1 defaults to quitting out, character2 stays headless).
      Applies **only** to sessions grimoire itself spawned headless -- a
      session grimoire merely attached to (already running before grimoire
      touched it) is left exactly as found on tab-close or grimoire exit
      either way, since grimoire did not start that session's lifecycle.
      Has nowhere of its own to live now that there is no separate
      saved-character store -- folds into the same per-character
      `<character>.yml` the "Per-character display configuration" section
      below already specs, keyed by the same `char_name` used to look the
      character up in `entry.yaml`, rather than a fourth storage location.
- [ ] Startup race handling for the launch case specifically -- reuse
      `SessionLocator`'s existing retry loop (`DEFAULT_RETRIES`/
      `DEFAULT_RETRY_INTERVAL`)

### Tab bar & multi-session view switching

Picked up (2026-09-15): session-object extraction, `SessionLogger` renaming,
the `Gtk::Notebook` shell, background-session handling, and the
duplicate-attach guard all moved to TASKS.md's "Multi-session shell
(standalone mode, phase 1)" section.

Widget/container architecture, resolved (user's own call, 2026-09-15): each
character's view is an embeddable widget (not its own top-level
`Gtk::Window`), switched via a **`Gtk::Notebook`** top tab bar --
GNOME-Terminal-style, chosen over a `Gtk::Stack` + `Gtk::StackSidebar`
left-hand list. One top-level shell window total. (Kept here, not moved, since
"Split view" below still cites it directly.)

### Split view

- [ ] Two-up `Gtk::Paned` (left|right) mode showing two sessions' views at
      once, independent of the tab bar's single-selection switch
- [ ] Depends on the "embeddable widget" call above -- a GTK widget has
      exactly one parent at a time, so showing a session in a split pane
      means removing its content widget from the `Gtk::Notebook` first, not
      literally showing it twice; reattach to the notebook when the split
      closes

#### Phase 2: pinning (2026-09-15)

One side of the split holds a single pinned character; the other side is
itself a second `Gtk::Notebook` holding every other open session as tabs
(character1 pinned || character2/3/4 tabbed). Sequenced after plain two-up
split above, not alongside it -- it reuses that split's reparenting
mechanism rather than needing its own, and validating that mechanism first
keeps this phase from having to debug both at once.

- [ ] A second, nested `Gtk::Notebook` inside the split's non-pinned pane,
      largely reusing the top-level Notebook's existing per-session
      tab-add/remove logic rather than duplicating it -- but a session's
      content widget can now live in three places instead of two (top-level
      Notebook, the pinned pane, or the nested Notebook), so whatever
      tracks "which container currently owns this widget" (see the
      duplicate-attach guard and the phase-1 session-object extraction)
      needs a third case, not just a boolean split/not-split
- [ ] Pin/unpin action on a tab (context menu or a pin icon) -- pinning
      moves that session's widget out of whichever Notebook currently holds
      it and into the dedicated pinned pane; unpinning reverses it
- [ ] Open policy question, resolve when this phase is picked up: where does
      a newly-attached or newly-launched character land while pinned+split
      is active -- the nested Notebook (i.e. "everything not pinned"), or
      the top-level Notebook, paused until the split closes?
- [ ] Open policy question, resolve when this phase is picked up: when the
      pin is released, or the split closes entirely, what happens to the
      nested Notebook's tabs -- do they merge back into the top-level
      Notebook, and in what order relative to tabs that were never split
      out at all?

### Per-character display configuration

Resolved (user's own call, 2026-09-15): full independent theme per
character, layered under grimoire-global settings that no character can
override.

- [ ] `config.yml` gains two roles: (a) shell-chrome-only settings no
      character file can override -- `Gtk::Notebook`/tab appearance, menu
      bar, the shell window itself -- and (b) the default `Theme` used for
      any session that has no character-specific file of its own
- [ ] A new `<character>.yml` (name matching the `char_name` looked up in
      Lich's `entry.yaml`, not a separate grimoire-side store -- see "Lich
      headless launch" above) is a full `Theme` override for that
      character's session content specifically, **plus** that character's
      close-behavior setting (leave running vs. send `quit`) from the same
      section -- one file, two concerns, both keyed off the same name.
      The theme half reuses `Config`'s existing field-by-field default
      mechanism (`config.rb`'s `#theme`, which already defaults each field
      independently against `Theme::DEFAULT`) -- the only change is the
      fallback base: when a character file is loaded, an unset field falls
      back to the **global `config.yml`'s already-resolved theme**, not
      hardcoded `Theme::DEFAULT`, so `character1.yml` only needs to state
      what it actually overrides
- [ ] `Config` needs an API split it does not have today: one loader for
      shell-chrome-only settings, one loader for a (base theme,
      optional-per-character-override-path) pair -- today's single
      `Config.load` returns one `Theme` with no notion of either distinction

### Widget visibility toggles

- [x] New boolean `Theme` fields (`show_vitals_bar`, `show_roundtime_bar`,
      `show_status_bar`) alongside the existing color/font fields in
      `lib/grimoire/theme.rb`, surfaced in `config.yml`/`config_template.rb`
      as `vitals.show`, `vitals.indicator_show`, `roundtime.show` -- see
      `docs/configuration.md`
- [x] `Window`'s build methods (`build_vitals_strip`, the roundtime-bar
      overlay, the active-indicators label) conditionally skip construction
      instead of always packing every widget; `#update_vitals`/
      `#update_roundtime_bar` guard against the widgets not existing
- [x] Open question resolved: config-file-only (restart to change), per the
      settings-file's existing "read only at startup" convention -- a live
      menu toggle is still open for whenever the shell/menu-bar work in the
      section above is picked up, since it would need the same boolean
      fields this item already ships
- [x] `show_vitals_bar`/`show_status_bar`/`build_vitals_strip` removed
      outright (2026-09-15), once `command_bar.command_vitals`/
      `status_indicators` fully superseded them as the out-of-the-box
      display -- see `docs/decisions.md`'s "Removed the top-of-window
      vitals strip..." entry. `show_roundtime_bar` is unaffected.
- [x] `vitals_colors`' `health`/`mana`/`stamina`/`spirit` fill colors moved
      into their own `Theme#command_vitals_colors` field, nested under
      `command_bar.command_vitals.*` in config.yml instead of the
      top-level `vitals:` section, once `command_vital_css` (`Window`) was
      confirmed to be their only remaining reader -- see `docs/decisions.md`'s
      "Split `vitals_colors`..." entry. `mind`/`encumbrance`/`stance` stay
      in `vitals_colors`.

