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
- [ ] Auto-send `look` on first prompt to populate initial room state — deferred to the Stream parsing section below: this needs real `<prompt>` tag detection from the tokenizer, not a substring guess on raw lines

## Stream parsing (protocol layer)

- [x] Tokenizer for the Simutronics XML-ish stream (tag vs. text segments) — not a single strip-all-tags regex — `lib/grimoire/tokenizer.rb`
- [x] Handle TCP chunk-boundary splits (tags/entities/CRLF spanning multiple reads) — buffer incomplete reads
- [x] Id-aware pushStream/popStream tracking (not just any bare close tag) — `lib/grimoire/stream_tracker.rb`; single current-stream value, not a nested stack (confirmed against lich-5 source; see `docs/decisions.md`)
- [x] Literal entity decoding (`&gt; &lt; &amp; &apos; &quot;`) at minimum
- [ ] Route non-narrative panel tags (`dialogData`, `openDialog`, `inv`, `room objs`/`room players`) to structured state, not the main text pane
- [ ] Structured room state (title, description, objects, players, exits, room number)
- [ ] Squelch `<prompt time="...">` spam from display while capturing `time` for round-timer state later (also unblocks the deferred "auto-send `look` on first prompt" item above)

## UI (GTK3)

- [x] Main window: scrollback text view plus command entry (MVP shape, matches rift-client's minimal starting point) — `lib/grimoire/window.rb`
- [x] Keep socket I/O off the GTK main thread; marshal updates back via `GLib.idle_add` (or equivalent) — `Connection#start_reading`'s thread never touches widgets; `App` marshals through `GLib::Idle.add` (`lib/grimoire/app.rb`); confirmed end-to-end against a fake Lich socket with the GLib main loop pumped manually
- [x] Command history (up/down arrow recall) — `Window#history_up`/`#history_down`
- [ ] Basic vitals/indicator area (health, mana, stamina, roundtime) fed by structured stream state — stretch goal, may land after the first working scrollback-and-input loop
- [x] Confirm `gem pristine`-built extensions render a window locally before building further UI — reconfirmed this session: real `Gtk::Window`/`Gtk::TextView`/`Gtk::Entry` construct and respond correctly both with a live `DISPLAY` and headless (no `DISPLAY`), so `spec/grimoire/window_spec.rb` runs in CI without Xvfb

## Testing

- [x] RSpec skeleton (`spec/` mirroring `lib/`), matching `ProfanityFE`'s `.rspec` convention
- [ ] Unit tests for the tokenizer against recorded/fixture stream samples (no live connection needed)
- [x] Unit tests for pushStream/popStream stack logic — `spec/grimoire/stream_tracker_spec.rb`
- [ ] Fixture capture: record a few real Lich frontend-port sessions for use as parser test fixtures (static data only, no live dependency in CI)

## Out of scope for MVP (explicitly deferred)

- [ ] Multi-pane layout (room window, indicator window, countdown window) beyond a minimal indicator strip
- [ ] Standalone EAS auth / SAL handoff path (rift-client's model) — only revisit if grimoire needs to run without Lich present
- [ ] Script/highlighting/macro system
- [ ] Packaging/distribution
