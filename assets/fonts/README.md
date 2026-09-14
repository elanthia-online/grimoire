# Bundled fonts

Drop font files here (`.ttf`/`.otf`, any subdirectory layout) and grimoire
registers them with Pango at startup via `Grimoire::Fonts.load_bundled!`
(`lib/grimoire/fonts.rb`) -- no system-wide font install required, on
Linux, Windows, or macOS. This exists specifically for **Overpass** and
**Overpass Mono**: open source (SIL Open Font License 1.1), free to
redistribute, but not preinstalled on Windows the way `Monospace`'s usual
fallbacks are -- bundling them here means grimoire's preferred look shows
up the same way on a fresh Windows install as it does on Linux.

Grimoire ships with this directory intentionally empty; the font files
themselves are a separate asset drop, not part of the source tree proper.
`Theme::DEFAULT`'s font family (`lib/grimoire/theme.rb`) already assumes
`Overpass Mono` is available and falls back to the generic `monospace`
family when it is not -- so grimoire still runs correctly with nothing in
this directory, just without the bundled look.

If you add font files here, include that font's own license file
alongside them (Overpass/Overpass Mono's OFL license text, if that is
what you are adding) so the redistribution terms travel with the binaries.
