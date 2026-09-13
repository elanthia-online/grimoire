# Tasks

Checkboxes render as tickable in GitHub's file view — this doubles as a lightweight board. Keep items small enough to check off in one sitting; split anything that stalls for more than a session or two.

MVP scope and the reasoning behind it are in [CLAUDE.md](CLAUDE.md); this list is the concrete breakdown.

## Repo setup

- [x] MIT license
- [x] `CLAUDE.md` (ground rules)
- [x] `README.md`
- [x] `TASKS.md`
- [x] Gemfile / gemspec skeleton (`gtk3` plus dev deps: `rspec`, `rubocop`)
- [x] Executable entry point (`grimoire`, at the repo root) — the `lich.rbw`-equivalent launcher; `lib/grimoire.rb` itself is only the library's require-aggregator, never meant to be run directly. Root-level rather than a gem `exe/` dir: grimoire is never `gem install`ed (see "Packaging/distribution" below), it's used from a cloned or archived copy of the repo, same as `lich.rbw` itself -- `spec.bindir`/`spec.executables` would only matter for an install path that is explicitly out of scope
- [x] `.rubocop.yml` matching `lich-5`/`ProfanityFE`'s profile (hash rockets table-aligned, ASCII-only, Ruby 4.0 target, most metrics disabled)
- [x] `.ruby-version` pinned (`system`, not `4.0.5` — no matching rbenv build in this sandbox; see CLAUDE.md note)
- [x] `.gitignore`
- [x] Skeleton directory layout (`lib/`, `spec/`)
- [x] Confirm `ruby-gtk3` native extensions build in the dev environment (extensions were already built; loads and opens a real window under `bundle exec` — see CLAUDE.md note on the bare-`require` json/red-colors clash)

## Connection to Lich

- [x] Confirm Lich's actual frontend-port handshake against `lich-5` source (`--detachable-client`/`--without-frontend` flags, expected identify string) — do not assume ProfanityFE's `SET_FRONTEND_PID` verbatim without checking lich-5's own listener code (confirmed real but optional; see `docs/decisions.md`)
- [x] TCP client: connect to configurable host/port (default `127.0.0.1`) — `lib/grimoire/connection.rb`
- [x] Identify/handshake on connect — `Connection#identify` sends `SET_FRONTEND_PID`
- [x] Distinguish connect-failure vs. established-then-dropped disconnect as separate code paths (rift-nexus hit this exact bug — see `docs/decisions.md`) — `ConnectError` at connect time vs. `on_disconnect` callback from the read loop
- [x] Outgoing command queue with throttle pacing (roughly 3/sec) to respect the server-side rate limit — `lib/grimoire/command_queue.rb`
- [x] Local `.command` to `;command` passthrough rewrite for Lich's script prefix — `lib/grimoire/command_rewrite.rb`
- [x] Auto-send `look` on first prompt to populate initial room state — deferred to the Stream parsing section below: this needs real `<prompt>` tag detection from the tokenizer, not a substring guess on raw lines — `App#handle_prompt`, fired via `NarrativeStream`'s `on_prompt` callback (backed by `lib/grimoire/prompt_tracker.rb`), one-shot on the first prompt seen

## Stream parsing (protocol layer)

- [x] Tokenizer for the Simutronics XML-ish stream (tag vs. text segments) — not a single strip-all-tags regex — `lib/grimoire/tokenizer.rb`
- [x] Handle TCP chunk-boundary splits (tags/entities/CRLF spanning multiple reads) — buffer incomplete reads
- [x] Id-aware pushStream/popStream tracking (not just any bare close tag) — `lib/grimoire/stream_tracker.rb`; single current-stream value, not a nested stack (confirmed against lich-5 source; see `docs/decisions.md`)
- [x] Literal entity decoding (`&gt; &lt; &amp; &apos; &quot;`) at minimum
- [ ] Route non-narrative panel tags to structured state, not the main text pane — `room objs`/`room players` are handled (see the structured-room-state item below). Everything else is, as of 2026-09-13, a **temporary wholesale squelch, not real routing**: `lib/grimoire/panel_tag_tracker.rb` (`PanelTagTracker`) drops `dialogData`, `openDialog`, `roommeta`, `spell`, `left`, `right`, `indicator`, `progressBar`, `resource`, `style`, `skin`, `image`, `pulse`, `label`, `compass`, `castTime` outright — confirmed necessary against a real live-captured session (see `docs/decisions.md`: 38 of 54 blank lines in a real parsed-output log traced to this, plus one garbled `spell`/`left`/`right` concatenation), not just the fixtures. `inv`'s container-listing shape (`spec/fixtures/inventory.xml` "Shape C") still leaks into narrative too and is not in `PanelTagTracker`'s list. Revisit `PanelTagTracker`'s drop list item-by-item once a UI actually wants any of this (prepared-spell/hands, vitals/indicator strip) — see `docs/decisions.md` for the exact migration path `room objs`/`room players` already took.
- [x] Structured room state (title, description, objects, players, exits, room number) — two separate entry points, not one: `enter_room` (move-triggered, `<nav rm='...'/>` plus a `clearStream`/`pushStream id='room'`/`compDef` bracket, resets every field) vs. `update_room` (periodic/passive, bare `<component id='room objs'|'room players'>` with no bracket, merges only the named field) — see `docs/decisions.md` — `lib/grimoire/room_state.rb` (plain holder) plus `lib/grimoire/room_tracker.rb` (the tag-watching state machine), wired into `NarrativeStream#room_state`; nothing consumes it yet since the vitals/indicator UI item below is still deferred
- [x] Squelch `<prompt time="...">` spam from display while capturing `time` for round-timer state later (also unblocks the deferred "auto-send `look` on first prompt" item above) — `lib/grimoire/prompt_tracker.rb`, wired into `NarrativeStream`; `time` is captured and handed to callers via `on_prompt`, but nothing yet turns it into structured round-timer state -- that consumer doesn't exist until the vitals/indicator UI item below lands

## UI (GTK3)

- [x] Main window: scrollback text view plus command entry (MVP shape, matches rift-client's minimal starting point) — `lib/grimoire/window.rb`
- [x] Keep socket I/O off the GTK main thread; marshal updates back via `GLib.idle_add` (or equivalent) — `Connection#start_reading`'s thread never touches widgets; `App` marshals through `GLib::Idle.add` (`lib/grimoire/app.rb`); confirmed end-to-end against a fake Lich socket with the GLib main loop pumped manually
- [x] Command history (up/down arrow recall) — `Window#history_up`/`#history_down`
- [ ] Basic vitals/indicator area (health, mana, stamina, roundtime) fed by structured stream state — stretch goal, may land after the first working scrollback-and-input loop
- [x] Confirm `gem pristine`-built extensions render a window locally before building further UI — reconfirmed this session: real `Gtk::Window`/`Gtk::TextView`/`Gtk::Entry` construct and respond correctly both with a live `DISPLAY` and headless (no `DISPLAY`), so `spec/grimoire/window_spec.rb` runs in CI without Xvfb

## Testing

- [x] RSpec skeleton (`spec/` mirroring `lib/`), matching `ProfanityFE`'s `.rspec` convention
- [x] Unit tests for the tokenizer against recorded/fixture stream samples (no live connection needed) — `spec/grimoire/tokenizer_spec.rb`'s "against real captured stream fixtures" block
- [x] Unit tests for pushStream/popStream stack logic — `spec/grimoire/stream_tracker_spec.rb`
- [x] Fixture capture: real Lich frontend-port sessions already exist in `_references/session-logs/` (18 captured GS sessions) and `_references/lich-5/benchmark/fixtures/` — extract into `spec/fixtures/` as separate real-excerpt files per concern (not one combined template): `room_transition.xml` (move-triggered, from the session logs), `room_update.xml` (passive, already present in `gs_sample.xml`), `inventory.xml`, `panel_dialogs.xml`; no fresh live capture needed unless a gap turns up — all four extracted with source-line citations (verified against the session logs) and wired into `tokenizer_spec.rb`/`narrative_stream_spec.rb`; `panel_dialogs.xml` is exercised only at the tokenizer level for now since its narrative-level filtering depends on the still-open "Route non-narrative panel tags" item above

## Out of scope for MVP (explicitly deferred)

- [ ] Multi-pane layout (room window, indicator window, countdown window) beyond a minimal indicator strip
- [ ] Standalone EAS auth / SAL handoff path (rift-client's model) — only revisit if grimoire needs to run without Lich present
- [ ] Script/highlighting/macro system
- [ ] Packaging/distribution
