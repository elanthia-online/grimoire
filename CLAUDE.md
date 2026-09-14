# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Grimoire is a lightweight Ruby/GTK3 front-end for Simutronics text-based games (GemStone IV, DragonRealms), designed to run **alongside** the lich-5 scripting engine rather than replace or duplicate it. See README.md for the one-paragraph pitch and TASKS.md for the current MVP task list.

## Ground rules (established 2026-09-12)

### Language & toolkit

- Ruby, targeting **4.0** (matches `lich-5` and `ProfanityFE`'s `.ruby-version` of 4.0.5 in this workspace — keep grimoire on the same target). Grimoire's own `.ruby-version` is pinned to `system` rather than `4.0.5`: this sandbox has no rbenv-managed 4.0.5 build, only a `system` Ruby reporting 4.0.6 — still within the 4.0 target, just not the exact patch version. Repin to `4.0.5` if a matching rbenv build becomes available.
- UI: **GTK3** via the `gtk3` gem (ruby-gnome). Confirmed buildable and loadable in this dev environment under `bundle exec` (native extensions were already built; `gem pristine gtk3 glib2 gio2 pango` is the fallback if a fresh install needs it). Note: a bare `ruby -e "require 'gtk3'"` outside Bundler can fail here on an unrelated `json`/`red-colors` version clash in the cairo dependency chain — always load gtk3 through Bundler (`bundle exec`), which resolves a working combination.

### Connection model — the central architectural decision

Grimoire attaches to **Lich's already-open frontend socket** (ProfanityFE's model: TCP to `127.0.0.1:<port>`, identify handshake, done) rather than performing its own EAS authentication (rift-client's model in rift-nexus). Lich owns login, session, and EAS; grimoire is a display-and-input client only.

**Why:** the project brief is explicit that grimoire runs "alongside the lich-5 scripting engine," not standalone. rift-client was offered as a UI/architecture reference (minimal scrollback-and-input shape, background-thread socket I/O), not as an auth-flow reference — rift-nexus's own `login` package exists because rift-nexus has no Lich to delegate to. Grimoire does. Duplicating EAS auth here would mean maintaining two credential/session flows for one game connection.

**Revisit if:** a standalone (no-Lich) launch mode ever becomes a real requirement — see TASKS.md's "out of scope for MVP" section.

**Host/port discovery:** in addition to explicit `--host`/`--port`, grimoire can resolve them automatically via `--character NAME`, which reads the `.session` file lich-5 writes at `$TMPDIR/simutronics/sessions/<Name>.session` when launched with both `--login <Name>` and `--detachable-client`. This is lich-5's existing simple session-file mechanism (`Lich::Common::Frontend.create_session_file`), not the separate auth-tokened "Active Sessions" API (`lib/api/active_sessions.rb` in lich-5) — that is a documented future alternative if the simple file approach proves too fragile (e.g. if multi-session enumeration or liveness heartbeats become necessary), not what is implemented today. `--list` enumerates every `.session` file currently in that directory (valid or not) without connecting to anything. See `lib/grimoire/session_locator.rb` and `docs/decisions.md`.

### Stream parsing

Real tag/text tokenization (ProfanityFE's approach), not a strip-all-tags regex (rift-client's stopgap in rift-nexus, which that project's own `docs/decisions.md` already flags as destroying tag semantics and a shortcut to fix properly later — not a pattern to copy here). Build the tokenizer correctly the first time; see TASKS.md's "stream parsing" section for the concrete pitfalls this needs to account for (chunk-boundary splits, id-aware pushStream/popStream tracking, panel-update tags that are not narrative text).

### Testing

- RSpec (matches `ProfanityFE`'s `.rspec` convention), specs under `spec/` mirroring `lib/`.
- The protocol/tokenizer layer must be unit-testable against static fixture data — no live Lich or game connection required for CI.
- Same for session discovery (`SessionLocator`): unit-tested against static fixture session files in a temp directory, no live lich-5 process required.

### Style (matches `lich-5` / `ProfanityFE` `.rubocop.yml` in this workspace)

- Hash rockets, table-aligned.
- ASCII-only identifiers and comments.
- Ruby 4.0 target, `NewCops: disable`.
- Most style/metrics/naming cops disabled — follow what is checked in, do not fight the linter config once `.rubocop.yml` lands (task in TASKS.md).

## Licensing & attribution

This project is MIT-licensed (see LICENSE). Reference projects consulted for behavioral and structural understanding only — never a source of copied code:

- **`lich-5`** — BSD-3-Clause (confirmed via rift-nexus's own license audit). Grimoire connects to Lich as a running process/socket peer; no Lich source is vendored or copied.
- **`ProfanityFE`** — **GPLv2** (confirmed: `ProfanityFE/LICENSE`). Used for architecture/pattern understanding only (event-bus structure, tag-handler dispatch, window-manager layout, Lich frontend-port handshake shape). Because GPLv2 is a strong copyleft and grimoire is MIT, no code, no verbatim structure, and no substantial expression may be copied or transliterated from ProfanityFE — describe the *behavior*, then implement independently. Attribute any nontrivial adapted technique (not just copied code) in a code comment and in `docs/decisions.md` if that file is added later.
- **`rift-nexus` `client` package** — sibling project in this same workspace, MIT-licensed, used as the UI/threading-shape reference for the MVP (single scrollback pane plus input, worker-thread socket I/O). No licensing concern (same author, same license), but its display-filter approach is a known-deferred shortcut, not a pattern to replicate — see "Stream parsing" above.
- **Wrayth, Stormfront** — closed source, if ever referenced: UX/behavior reference only, from observed play — never source or binary.

## Related workspace context

This repo is a member of the `EoL` workspace (`/home/msawyer/EoL`); see the workspace root `CLAUDE.md` for the full set of sibling repos and cross-repo conventions.
