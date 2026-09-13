# Tasks

Checkboxes render as tickable in GitHub's file view — this doubles as a lightweight board. Keep items small enough to check off in one sitting; split anything that stalls for more than a session or two.

MVP scope and the reasoning behind it are in [CLAUDE.md](CLAUDE.md); this list is the concrete breakdown.

## Repo setup

- [x] MIT license
- [x] `CLAUDE.md` (ground rules)
- [x] `README.md`
- [x] `TASKS.md`
- [x] Gemfile / gemspec skeleton (`gtk3` plus dev deps: `rspec`, `rubocop`)
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

- [ ] Tokenizer for the Simutronics XML-ish stream (tag vs. text segments) — not a single strip-all-tags regex
- [ ] Handle TCP chunk-boundary splits (tags/entities/CRLF spanning multiple reads) — buffer incomplete reads
- [ ] Id-aware pushStream/popStream stack tracking (not just any bare close tag)
- [ ] Literal entity decoding (`&gt; &lt; &amp; &apos; &quot;`) at minimum
- [ ] Route non-narrative panel tags (`dialogData`, `openDialog`, `inv`, `room objs`/`room players`) to structured state, not the main text pane
- [ ] Structured room state (title, description, objects, players, exits, room number)
- [ ] Squelch `<prompt time="...">` spam from display while capturing `time` for round-timer state later (also unblocks the deferred "auto-send `look` on first prompt" item above)

## UI (GTK3)

- [ ] Main window: scrollback text view plus command entry (MVP shape, matches rift-client's minimal starting point)
- [ ] Keep socket I/O off the GTK main thread; marshal updates back via `GLib.idle_add` (or equivalent)
- [ ] Command history (up/down arrow recall)
- [ ] Basic vitals/indicator area (health, mana, stamina, roundtime) fed by structured stream state — stretch goal, may land after the first working scrollback-and-input loop
- [ ] Confirm `gem pristine`-built extensions render a window locally before building further UI

## Testing

- [x] RSpec skeleton (`spec/` mirroring `lib/`), matching `ProfanityFE`'s `.rspec` convention
- [ ] Unit tests for the tokenizer against recorded/fixture stream samples (no live connection needed)
- [ ] Unit tests for pushStream/popStream stack logic
- [ ] Fixture capture: record a few real Lich frontend-port sessions for use as parser test fixtures (static data only, no live dependency in CI)

## Out of scope for MVP (explicitly deferred)

- [ ] Multi-pane layout (room window, indicator window, countdown window) beyond a minimal indicator strip
- [ ] Standalone EAS auth / SAL handoff path (rift-client's model) — only revisit if grimoire needs to run without Lich present
- [ ] Script/highlighting/macro system
- [ ] Packaging/distribution
