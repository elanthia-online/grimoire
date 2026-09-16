# Indicator icons

`assets/indicators/*.png` back the live 4-slot indicator block in the game window (`SessionView#build_indicator_block`) -- one file per confirmed wire `IconXXXX` id. The id-to-file mapping lives in `Grimoire::IndicatorGroups` (`lib/grimoire/indicator_groups.rb`); see also `docs/decisions.md`.

## Attribution

Source: [game-icons.net](https://game-icons.net/), licensed
[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). Every icon here
is recolored from its original game-icons.net source (black/transparent to
this set's own palette) -- no other modification (shape, composition) was
made, noted here per CC BY's own requirement to flag changes.

| File | Icon | Artist |
|---|---|---|
| `stunned.png` | Laser sparks icon | Lorc |
| `standing.png` | Person icon | Delapouite |
| `prone.png` | Falling icon | sbed |
| `sitting.png` | Meditation icon | Lorc |
| `kneeling.png` | Kneeling icon | Delapouite |
| `bleeding.png` | Bleeding wound icon | Lorc |
| `poisoned.png` | Biohazard icon | Lorc |
| `diseased.png` | Paramecia icon | Lorc |
| `hidden.png` | Hidden icon | Lorc |
| `dead.png` | Soul icon | Delapouite |
| `invisible.png` | Invisible icon | Delapouite |
| `joined.png` | Shadow follower icon | Lorc |
| `webbed.png` | Spider web icon | Lorc |
