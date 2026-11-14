# RetroMUD GUI for Mudlet

Geyser GUI for [RetroMUD](https://www.retromud.org). Works with, but does not require,
[retromud-mudlet-mapper](../retromud-mudlet-mapper): the two talk only through events (`rmap.onRoom`).

## Install

1. Download `retromud-gui.mpackage`. You can get it from the `dist` folder of this repository or from the Releases page. Both files are the same.
2. In Mudlet, open the Package Manager (`Alt+O`), click Install, and pick the file.
3. Also install the mapper package (`retromud`) if you want map features.

## Build

Needs Java and [Muddler](https://github.com/demonnic/muddler/releases) (`muddle` on PATH):

    ./build.sh        # builds, then copies the package to dist/

## Release

1. Raise `version` in `mfile`.
2. Run `./build.sh`.
3. Commit `dist/retromud-gui.mpackage` and the version change.
4. Attach the same file to a GitHub release:

        gh release create v<version> dist/retromud-gui.mpackage --generate-notes

## Status

The GUI is built and works in a live Mudlet profile: the frame (status bar and two columns), six planet themes, vitals gauges, a tabbed chat panel, buttons, and a map host. See `doc/design.md` for the modules and `doc/spec/` for the specifications.

Themes: click the theme button at the top right of the status bar and pick a planet. Or type `rgui theme` (list themes), `rgui theme <name>`, `rgui theme reload`. Layout: `rgui layout wide|compact|auto`.

Known limits: the map host builds its own map widget until the mapper creates the `rmap.map` pane. The map toggle, the `where`, `scan` and `undo` buttons use the mapper's commands. Not everything has been judged by eye yet.

## License

[MIT](LICENSE). The pixel art in `src/resources/themes/` was generated with Runware for this project.
