# grimoire

A lightweight Ruby/GTK3 front-end for Simutronics text-based games (GemStone IV, DragonRealms), designed to run alongside the [lich-5](https://github.com/elanthia-online/lich-5) scripting engine rather than replace it.

Lich owns authentication and the live game connection; grimoire attaches to Lich's frontend socket as a display-and-input client, in the same spirit as [ProfanityFE](https://github.com/elanthia-online/ProfanityFE) but built on GTK3.

## Status

Grimoire runs as a standalone shell: it starts with no character connected, and sessions are opened from its own menu. Each attached character gets its own tab, running independently -- its socket, scrollback, vitals and roundtime keep updating whether or not its tab is the visible one. Under each tab is the working scrollback-and-input loop: filter the incoming stream down to narrative text, and send commands back.

See [TASKS.md](TASKS.md) for the current task list and [CLAUDE.md](CLAUDE.md) for working conventions and licensing/attribution policy.

## Running it

Lich must already be running with a frontend socket open (`--detachable-client=PORT`, or `=auto` to let it pick one -- see `docs/decisions.md`). Then:

```sh
bundle install
./grimoire                    # blank shell; attach characters from the Session menu
./grimoire --character NAME   # opens the shell with NAME already attached in the first tab
./grimoire --port PORT [--host HOST]   # or connect manually; HOST defaults to 127.0.0.1
./grimoire --list             # list characters with an active Lich session, then exit
```

With no arguments grimoire opens its shell with nothing connected. **Session > Attach to session...** lists whatever Lich sessions are currently running and opens the chosen one in a new tab; sessions already open in a tab are left out of that list. `--character`/`--port` do not bypass the shell -- they open it with that session pre-attached as the first tab.

Each tab has its own close button. Closing a tab disconnects grimoire from that session only: Lich itself keeps running and the character stays logged in, so it can be attached again afterwards. Closing the last tab returns to the blank shell rather than exiting.

`--character` requires Lich to have also been started with `--login NAME`, so it knows which session to write. See `docs/decisions.md` for how discovery and the `--list`/reconnect-retry behavior work.

## Configuration

Appearance (colors, fonts, padding) is controlled by a YAML settings file, auto-created on first run at `configs/config.yml`. See [docs/configuration.md](docs/configuration.md) for the full settings reference.

## License

MIT — see [LICENSE](LICENSE). Reference projects consulted during development (lich-5, ProfanityFE, rift-nexus, and others) are used for behavioral and structural understanding only — see [CLAUDE.md](CLAUDE.md) for the full policy.
