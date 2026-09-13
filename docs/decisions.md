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
