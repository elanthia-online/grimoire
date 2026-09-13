# Decisions

Notes on nontrivial choices, and on findings confirmed directly against reference-project source rather than assumed. See CLAUDE.md for the licensing/attribution policy governing what reference projects may be used for.

## Lich frontend-port handshake (confirmed against lich-5 source, 2026-09-13)

TASKS.md's "Connection to Lich" section warned not to assume ProfanityFE's `SET_FRONTEND_PID` convention verbatim without checking lich-5's own listener code. Confirmed directly:

- **The listener is opt-in, not always-on.** Lich only opens a frontend/detachable-client TCP socket when started with `--detachable-client=VALUE` (accepted forms: `PORT`, `auto`, `HOST:PORT`, `[IPV6]:PORT`; `auto` lets the OS assign a port). Default bind host is `127.0.0.1` unless `--bind-address` overrides it. See `lib/main/detachable_client_target.rb` and `lib/main/main.rb` (around the `detachable_client_thread` block).
- **`SET_FRONTEND_PID <pid>` is real and lich-5 does parse it** (`lib/global_defs.rb`, `handle_detachable_client`, matching `/^SET_FRONTEND_PID\s+(\d+)\s*$/`), matching ProfanityFE's convention. It is optional, not a required identify/auth step -- the socket accepts and dispatches input with or without it. It only feeds `Frontend.set_from_client`, used for frontend-differentiated behavior elsewhere in Lich.
- **On accept, Lich immediately pushes initial state** to the new client: vitals progress bars (mana/health/spirit/stamina), status indicators, prepared spell, and compass exits (`detachable_client_send_init`). It does **not** include room description, room objects, or room players -- so grimoire still needs to auto-send `look` on first prompt to populate those, per TASKS.md.
- **Outgoing protocol is plain newline-terminated text lines.** Lich's own detachable-client handler prepends its internal `$cmd_prefix` (`'<c>'`) server-side before dispatching each line (`lib/global_defs.rb`, `handle_detachable_client` / `dispatch_client_input`). Grimoire must never send `<c>` itself -- that tag is added by Lich, not expected from the client.
- **The actual Lich script-command prefix character is `;`** (or `,` for the Genie frontend) -- `$lich_char` / `$lich_char_regex` in `lib/main/main.rb`. This is what a local `.command` -> `;command` passthrough rewrite in grimoire's input box would target; it is a grimoire-side UX convenience, not something the protocol requires (typing `;command` directly works with no rewriting at all).
- **Connect-failure and mid-session-drop are genuinely different code paths on the Lich side too**: the accept loop's `rescue` (server-side accept errors) is distinct from `client.gets` returning `nil` on the per-client read loop (clean EOF/disconnect). This confirms TASKS.md's note (and the bug rift-nexus hit) that grimoire's own TCP client needs separate handling for "never connected" vs. "connected, then dropped."

Sources: `_references/lich-5/lib/main/detachable_client_target.rb`, `_references/lich-5/lib/main/main.rb`, `_references/lich-5/lib/global_defs.rb` (`detachable_client_send_init`, `handle_detachable_client`, `dispatch_client_input`, `do_client`).

## pushStream/popStream is a single current-stream value, not a nested stack (confirmed against lich-5 source, 2026-09-13)

TASKS.md's Stream parsing section called this "Id-aware pushStream/popStream stack tracking." Confirmed directly against `_references/lich-5/lib/common/xmlparser.rb`: Lich's own reference parser tracks a single `@current_stream` value plus an `@in_stream` flag -- `pushStream` overwrites `@current_stream` with the new id (there is no push onto a saved stack), and `popStream` always drops back to narrative regardless of any id it carries or of what was open before. A `pushStream` seen while already inside another stream simply replaces the current id; the original is not restored when the inner one closes. The real protocol never nests streams, so there is nothing to restore.

`Grimoire::StreamTracker` (`lib/grimoire/stream_tracker.rb`) implements this single-current-value model rather than a literal stack, to match confirmed behavior instead of the stronger semantics the task wording implied.

Source: `_references/lich-5/lib/common/xmlparser.rb` (around the `pushStream`/`popStream` handling in the tag-open callback).

## Executable launcher lives at the repo root, not in a gem `exe/` directory (2026-09-13)

The initial pass at the launcher put it in `exe/grimoire` with `spec.bindir`/`spec.executables` set in `grimoire.gemspec`, following plain RubyGems convention (mirrors how `bundle gem` scaffolds a new gem). That convention exists to support `gem install` copying the file onto `PATH` and RubyGems auto-activating `lib/` for it.

Grimoire will never be `gem install`ed -- "Packaging/distribution" is explicitly out of scope for MVP (see TASKS.md), and the only distribution paths are a git clone or a source archive, same as `lich-5` itself. Building the launcher's location around an install mechanism that will not be used is designing for a requirement the project has explicitly deferred. The launcher was moved to a root-level `grimoire` script (matching `lich.rbw`'s own placement, for the same reason: no packaging layer to hand it off to), using `require_relative 'lib/grimoire'` instead of a bare `require 'grimoire'` since it can no longer rely on RubyGems/Bundler activating `lib/` for it as an installed executable. `spec.bindir`/`spec.executables` were removed from the gemspec accordingly.

The gemspec itself was kept (not folded into a plain `Gemfile` with inline `gem` lines): `Gemfile`'s `gemspec` directive still needs it for the `gtk3`/`rspec`/`rubocop` dependency declarations and for `spec.require_paths = ['lib']`, which is what puts `lib/` on the load path for `bundle exec`. That mechanism is orthogonal to whether the gem is ever published -- it is what makes local development work at all, so removing it would only add cost (re-wiring the load path some other way) with no offsetting benefit.

## Room transitions and periodic room updates are two distinct events (confirmed against captured GS session logs, 2026-09-13)

TASKS.md's "Structured room state" item cannot be a single "on room tag, replace room state" handler -- real traffic shows two genuinely different triggers that a room-state tracker must handle differently:

- **Move-triggered transition (new room):** entering a new room via a move action (`north`, `south`, etc.) arrives bracketed by `<clearStream id='room'/><pushStream id='room'/>`, carries `<compDef id='room desc'|'room objs'|'room players'|'room exits'>` for all four fields together, and is keyed by a room identity change via `<nav rm='NNNN'/>`. This is a full reset: the previously known room state is discarded and replaced wholesale.
- **Periodic/passive update (same room):** already visible in `lich-5/benchmark/fixtures/gs_sample.xml` -- bare `<component id='room objs'>` / `<component id='room players'>` tags recur repeatedly mid-combat with **no** accompanying `<nav>` and **no** `clearStream`/`pushStream id='room'`/`compDef` bracket (e.g. another creature's death changing what "you also see," or a player entering/leaving). This is a partial merge into the currently-known room, not a new room -- the identity (title, description, exits, room number) has not changed and must not be reset or cleared just because an objs/players field arrived.

**Implication for the tracker's design:** it needs two entry points, not one -- `enter_room(...)` (fires only on the `nav rm=`/`clearStream`+`pushStream id='room'` bracket; resets every field) and `update_room(...)` (fires on a bare `component id='room objs'|'room players'` outside that bracket; merges into whichever fields it names, leaves the rest untouched). Treating every `room objs`/`room players` tag as transition evidence would spuriously "enter" a new room on every passive update.

**Implication for fixtures:** the planned `spec/fixtures/` split (see conversation, not yet built) needs a `room_transition.xml` (move-triggered, full bracket, from the session-logs GSF capture) *and* a separate `room_update.xml` (passive, bare component tags, already extractable from the existing `gs_sample.xml` reference) as two distinct examples -- one file covering both would blur the exact distinction this note exists to preserve.
