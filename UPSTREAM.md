# Upstream issues

Issues in other projects (mostly lich-5) that block grimoire work, that grimoire work depends on, or that are a known risk to how grimoire behaves. Some may be implemented by this project's own author upstream; they are still tracked here, since grimoire cannot rely on a change until it is merged and released.

The work these affect lives in [BACKLOG.md](BACKLOG.md) or [TASKS.md](TASKS.md); this file only tracks the upstream side. Local drafts of submitted proposals are kept under `_references/` (not committed).

**Kind**
- **Blocker:** grimoire work is on hold until the issue is resolved.
- **Dependency:** grimoire works today, but a planned improvement needs the upstream change.
- **Risk:** grimoire behavior can be wrong or misleading until the upstream change lands.

**Keeping this current:** when an issue's status changes, update its row and entry. Once the change is released and grimoire no longer needs a fallback, move the entry to "Resolved" with the release that carried it.

## Open

| Issue | Kind | Status | Implementer | Affects |
|---|---|---|---|---|
| [lich-5#1642](https://github.com/elanthia-online/lich-5/issues/1642): begin/end markers around the detachable-client init push | Blocker | Submitted 2026-09-16, in community review | Undecided (possibly this project's author) | BACKLOG.md: "Lich init push begin/end markers (on hold)" |
| [lich-5#1646](https://github.com/elanthia-online/lich-5/issues/1646): report `--reconnect` in the session descriptor file | Dependency, Risk | Submitted 2026-09-16, awaiting review | Undecided (possibly this project's author) | BACKLOG.md: "Headless launch follow-ups" |
| [lich-5#1647](https://github.com/elanthia-online/lich-5/issues/1647): identify the game instance in session descriptor files | Risk, Dependency | Submitted 2026-09-16, awaiting review | Undecided (possibly this project's author) | BACKLOG.md: "Headless launch follow-ups" |

### lich-5#1642: `<lichInit>` begin/end markers

- **Local draft:** `_references/lich_init_proposal.md`
- **Why grimoire needs it:** a frontend cannot tell when Lich's init push (vitals, indicators, hands, compass) has arrived. Grimoire sends its first `look` on the first prompt, which can land before the push, and in a quiet room no prompt may arrive at all. See docs/decisions.md's "Lich init push, updated per game" entry.
- **Grimoire today:** first-prompt `look`, unchanged.
- **On hold:** do not implement in lich-5 or grimoire until review settles the tag name, attributes and scope.
- **Unblocked when:** the issue is accepted with a final design. Grimoire can then implement against it, keeping today's behavior as the fallback for a Lich that sends no `begin` marker.

### lich-5#1646: `reconnect` in the session descriptor

- **Local draft:** `_references/lich_session_reconnect_proposal.md`
- **Why grimoire needs it:** a session file carries only `name`, `host` and `port`, so grimoire cannot tell whether a running Lich was started with `--reconnect`. In the user's live testing (2026-09-16), a character launched through the Connect dialog's same-account "Launch anyway" override was logged out again when the other character's Lich reconnected.
- **Risk today:** the override may not hold, and grimoire cannot say which case applies.
- **Grimoire today:** the same-account warning says that a Lich started with `--reconnect` will log back in and log the launched character out instead (docs/decisions.md, "One Connect dialog for attaching and launching").
- **Not blocked:** the headless launch phase is complete without it. Reading other processes' command lines was considered and rejected as platform-specific and unreliable (see the draft's alternatives).
- **Unblocked when:** the field is merged and released. Grimoire can then word the warning definitively when the field is present, and keep the current caveat when it is absent (an older Lich).

### lich-5#1647: game instance in session descriptor files

- **Local draft:** `_references/lich_session_game_code_proposal.md`
- **Why grimoire needs it:** a session file is named `<Name>.session` and carries no game instance, but one character name can run on several instances at once (GST characters are copies of main-game characters, so it is the normal case there). A second Lich for the name overwrites the first one's file, and the first to exit deletes it.
- **Risk today:** the Connect dialog marks every instance of a name as running when any one is and attaches to whichever session the file names, so the other instance cannot be launched from it. The post-launch wait and the dropped-tab rescan both match by name and can pick up another instance's session.
- **Grimoire today:** no mitigation; every favorite row for a name shares one session status (see `ConnectList`'s class comment in lib/grimoire/connect_list.rb).
- **Same login across instances:** one account allows one logged-in character per game (GS3, GST and GSF share a login), so once instances can be told apart, launching Sparrow on GST while Sparrow runs on GS3 logs the GS3 session out. Grimoire's same-account check must cover that case when this lands.
- **Unblocked when:** lich-5 identifies the instance in the descriptor and, ideally, in the file name. Grimoire can then key sessions by name and game code, and fall back to name only for an older Lich.

## Resolved

None yet.
