# grimoire

A lightweight Ruby/GTK3 front-end for Simutronics text-based games (GemStone IV, DragonRealms), designed to run alongside the [lich-5](https://github.com/elanthia-online/lich-5) scripting engine rather than replace it.

Lich owns authentication and the live game connection; grimoire attaches to Lich's frontend socket as a display-and-input client, in the same spirit as [ProfanityFE](https://github.com/elanthia-online/ProfanityFE) but built on GTK3.

## Status

Grimoire runs as a standalone shell: it starts with no character connected, and sessions are opened from its own menu. Each attached character gets its own tab, running independently -- its socket, scrollback, vitals and roundtime keep updating whether or not its tab is the visible one. Under each tab is the working scrollback-and-input loop: filter the incoming stream down to narrative text, and send commands back.

See [TASKS.md](TASKS.md) for the current task list, [UPSTREAM.md](UPSTREAM.md) for lich-5 issues that grimoire work depends on, and [CLAUDE.md](CLAUDE.md) for working conventions and licensing/attribution policy.

## Running it

Grimoire either attaches to a Lich that is already running with a frontend socket open (`--detachable-client=PORT`, or `=auto` to let it pick one -- see `docs/decisions.md`), or launches Lich headless itself for one of your Lich favorites, which needs `lich.dir` set in `config.yml` (see `docs/configuration.md`). Then:

```sh
bundle install
./grimoire                    # blank shell; attach or launch characters from Session > Connect...
./grimoire --character NAME   # opens the shell with NAME already attached in the first tab
./grimoire --port PORT [--host HOST]   # or connect manually; HOST defaults to 127.0.0.1
./grimoire --list             # list characters with an active Lich session, then exit
```

With no arguments grimoire opens its shell with nothing connected. **Session > Connect...** lists your Lich favorites plus any other Lich session currently running, each marked open in a tab, running, launching or not running. Choosing a running session attaches it in a new tab (or focuses its tab if already open). Choosing a favorite that is not running launches it headless (`lich.rbw --login NAME --headless auto` with the favorite's game) and attaches it once Lich has logged in; the title bar shows `Launching NAME...` meanwhile, and if Lich exits or takes more than 2 minutes, a dialog shows its last output. If another character on the same account is already logged in to the same game (GS3, GST and GSF share one login; so do DragonRealms' instances), grimoire warns first, since launching would log that character out. If that other character's Lich was started with `--reconnect`, it logs straight back in and logs the launched character out instead; grimoire cannot tell from the session file, so the warning says so. Launching needs `lich.dir` in `config.yml` set to your lich-5 directory (see `docs/configuration.md`); without it the dialog still attaches to running sessions. `--character`/`--port` do not bypass the shell -- they open it with that session pre-attached as the first tab.

Each tab has its own close button. Closing a tab disconnects grimoire from that session only: Lich itself keeps running and the character stays logged in, so it can be attached again afterwards. Closing the last tab returns to the blank shell rather than exiting.

If a session's connection drops (Lich restarted, crashed, or quit), its tab stays open with its scrollback, is labelled `(disconnected)`, and stops accepting commands. Grimoire looks for that character's Lich session again every 5 seconds and reattaches it in the same tab as soon as it is back -- on whatever port it came back on, so a Lich using `--detachable-client=auto` with `--reconnect` is picked up too. A tab still disconnected after about 5 minutes closes itself. A `--port` attach is matched to its character by the Lich session file on that port, so it reattaches the same way.

`--character` requires Lich to have also been started with `--login NAME`, so it knows which session to write. See `docs/decisions.md` for how discovery and the `--list`/reconnect-retry behavior work.

## Configuration

Appearance (colors, fonts, padding) is controlled by a YAML settings file, auto-created on first run at `configs/config.yml`. See [docs/configuration.md](docs/configuration.md) for the full settings reference.

## License

MIT — see [LICENSE](LICENSE). Reference projects consulted during development (lich-5, ProfanityFE, rift-nexus, and others) are used for behavioral and structural understanding only — see [CLAUDE.md](CLAUDE.md) for the full policy.
