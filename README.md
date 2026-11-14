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

Skeleton: a top status bar that shows the current room (from the mapper) and tears down cleanly on uninstall.
Next: prompt-parsed vitals, chat miniconsole, map container, button bar.
