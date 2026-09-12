# grimoire

A lightweight Ruby/GTK3 front-end for Simutronics text-based games (GemStone IV, DragonRealms), designed to run alongside the [lich-5](https://github.com/elanthia-online/lich-5) scripting engine rather than replace it.

Lich owns authentication and the live game connection; grimoire attaches to Lich's frontend socket as a display-and-input client, in the same spirit as [ProfanityFE](https://github.com/elanthia-online/ProfanityFE) but built on GTK3.

## Status

Early scaffolding — see [TASKS.md](TASKS.md) for the current MVP task list and [CLAUDE.md](CLAUDE.md) for working conventions and licensing/attribution policy.

## License

MIT — see [LICENSE](LICENSE). Reference projects consulted during development (lich-5, ProfanityFE, rift-nexus, and others) are used for behavioral and structural understanding only — see [CLAUDE.md](CLAUDE.md) for the full policy.
