# RetroMUD GUI for Mudlet

This package adds a graphical interface to Mudlet for [RetroMUD](https://www.retromud.org). It has a status bar, two side columns, themes, health bars, a party panel, a chat panel, buttons, and aliases that walk you to world exits.

The package works with [retromud-mudlet-mapper](../retromud-mudlet-mapper) but does not need it. The two packages talk only through events (`rmap.onRoom`).

## Install

1. Download `retromud-gui.mpackage`. The `dist` folder of this repository and the Releases page have the same file.
2. In Mudlet, open the Package Manager (`Alt+O`), click Install, and pick the file.
3. To get map features, also install the mapper package (`retromud`).

## Build

You need Java and [Muddler](https://github.com/demonnic/muddler/releases). The `muddle` command must be on your PATH.

    ./build.sh        # builds, then copies the package to dist/
    sh test/run.sh    # unit tests, needs a lua binary on PATH

## Release

1. Raise `version` in `mfile`.
2. Run `./build.sh`.
3. Commit `dist/retromud-gui.mpackage` and the version change.
4. Attach the same file to a GitHub release:

        gh release create v<version> dist/retromud-gui.mpackage --generate-notes

## Status

The GUI works in a live Mudlet profile. It has these parts:

- The frame: a status bar and two columns.
- Six planet themes.
- Health bars (HP, SP, EP) with the numbers on the bars.
- A party panel.
- A chat panel with tabs and a font size control.
- Buttons.
- World transport aliases.
- A map host.

`doc/design.md` describes the modules. `doc/spec/` has the specifications.

Your own buttons: twelve buttons (3 rows of 4) sit under the chat. To set the name and the command of a button, right click it or click an empty one. A click on a button sends its command as if you typed it. If a Mudlet alias has that name, the alias runs. Otherwise the text goes to the game. Mudlet saves the buttons in `retromud-gui-settings.lua`.

Known limits:

- The map host builds its own map widget until the mapper creates the `rmap.map` pane.
- The map toggle and the `where`, `scan` and `undo` buttons use the commands of the mapper.
- Not every screen has been checked by eye yet.

## Themes

A theme sets the colors, the font sizes, and the pictures of the GUI. To change the theme, click the theme button at the top right of the status bar and pick a planet. You can also type these commands:

    rgui theme            list the themes and show the active one
    rgui theme <name>     switch theme (welstar, crypt, sosel, wysoom, raji, perdow)
    rgui theme reload     read your theme files again and apply the active theme
    rgui layout wide|compact|auto

### Edit a theme

Your changes go in the folder `retromud-gui-theme/` in your Mudlet profile folder. The profile folder is the folder that the Mudlet function `getMudletHomeDir()` returns, for example `~/.config/mudlet/profiles/<profile>`. An uninstall does not delete `retromud-gui-theme/`.

1. Create the folder `retromud-gui-theme/` if it does not exist.
2. Add or change the files that the next two sections describe.
3. Type `rgui theme reload`.

#### Change colors and fonts

Create the file `retromud-gui-theme/theme.lua`. The file must return a table. Only the values that you list change. They apply on top of the active theme. The GUI ignores an unknown key and a value of the wrong type, and it still applies the rest of the file.

    return {
      colors = {
        hp = { 255, 100, 100 },        -- { red, green, blue }, each 0 to 255
        sp = { 255, 180, 70 },
        ep = { 140, 210, 100 },
        text = { 236, 228, 220 },
        surface = { 20, 18, 24 },      -- panel background
      },
      fonts = { size = 11 },           -- you can also set family = "Some Font" and sizeSmall = 9
    }

You can set these color names: `surface`, `surfaceAlt`, `text`, `textMuted`, `accent`, `border`, `good`, `warn`, `danger`, `hp`, `sp`, `ep`, and `map = { background = {..}, exits = {..} }`.

The numbers on the HP, SP and EP bars are always black. Keep the three bar colors light so that the numbers stay easy to read.

`doc/spec/theming.md` section 5 has the full table of keys. `src/scripts/theme/presets.lua` has the values of the built-in themes. You can copy values from it.

#### Change the pictures

Put PNG files with these exact names in `retromud-gui-theme/`. A file in this folder replaces the picture of the active theme, for every theme.

| File | Used for | Size of the art (px) |
|---|---|---|
| `window.png` | the column background (a tile) | 128 x 128 |
| `panel.png` | the panels | 64 x 64, 16 px frame |
| `statusbar.png` | the status bar | 64 x 32 |
| `button.png` | the buttons | 48 x 48, 12 px frame |
| `tab.png`, `tabActive.png` | the chat tabs | 48 x 48, 12 px frame |

The GUI stretches the frame of a picture around the text. The middle of the picture must be one flat color, so that the text stays easy to read. `doc/spec/theming.md` section 6 has the rules. To go back to the picture of the theme, delete your file.

## Make new theme art

The pictures of the six built-in themes come from the script `tools/theme-art/generate.py`. The script asks the Runware image service for each picture, then cleans it up into pixel art. You only need this if you want to make or change the art of a built-in theme. To change the pictures for yourself, use the files in `retromud-gui-theme/` (see "Change the pictures").

You need Python 3 and the Pillow library, and a Runware API key. Put the key in the environment variable `RUNWARE_API_KEY`. Do not write the key in a file, and do not commit it.

Run all commands from the repository root:

    python3 tools/theme-art/generate.py --dry-run                 # print the prompts, no API call
    RUNWARE_API_KEY=... python3 tools/theme-art/generate.py --theme perdow --role panel
    RUNWARE_API_KEY=... python3 tools/theme-art/generate.py --theme perdow --role panel --seed 7
    python3 tools/theme-art/generate.py --from-raw                # redo the cleanup, no API call
    python3 tools/theme-art/generate.py --derive-tabs             # rebuild tab.png and tabActive.png from button.png

Without `--theme` and `--role`, the script makes every picture. The theme names are `welstar`, `crypt`, `sosel`, `wysoom`, `raji`, and `perdow`. The role names are `window`, `panel`, `statusbar`, `button`, `tab`, and `tabActive`. The same seed gives a similar picture, so use `--seed` to try again with another one.

The script writes the pictures to `src/resources/themes/<theme>/<role>.png`. It keeps the raw downloads in `tmp/theme-art-raw/`, which git ignores. To try a picture without replacing the real one, add `--out <folder>`.

### Edit the prompts

The prompts are in `tools/theme-art/generate.py`. A full prompt has four parts, and you edit each part in its own place:

- `STYLE`: the pixel art look that every picture shares. `NEGATIVE` lists what to avoid.
- `MOTIF`: one line for each theme, with its colors and its images. To change what a theme looks like, edit its line.
- `ROLES`: the text for each kind of picture, with its size and its frame.
- `ROLE_OVERRIDE`: a text for one theme and one role together. It replaces the `ROLES` text for that picture only. Use it when one picture needs its own idea.

The colors of a theme come from `src/scripts/theme/presets.lua`, so the picture and the theme match. The script paints the middle of each frame in a flat theme color, so the text stays easy to read.

To test a new motif once, run `--motif "your text" --theme <theme> --dry-run`. Remove `--dry-run` to make the picture. This replaces the motif of that theme for the one run and does not change the file.

After you make the pictures, run `./build.sh` and install the new package in Mudlet. `doc/spec/theming.md` section 7a has more detail.

## Chat font

Two small buttons, `-` and `+`, are at the bottom right of the chat window. Each tap changes the size of the chat text by 1, from 6 to 24. Mudlet saves the size.

## Party bars

The panel under your own HP, SP and EP bars shows the name and the bars of each party member. It has room for 8 people.

To fill the panel, type `pssa`. The panel shows the last output of `pssa`. To refresh it, type `pssa` again. You can also put `pssa` on a Mudlet trigger for combat. Your own bars update from your prompt.

## World transport

The world transport aliases walk you to a world exit. An alias is a short command that runs a script. These aliases send one plain command for each step. They do not use the map. For this reason, each walk works only from the room in the table below. If you start in another room, the walk ends in the wrong place.

The routes come from the [world exits page](https://retrowiki.wikidot.com/world-exits) of the RetroWIKI (page revision 2125, 18 July 2025). The routes are in `src/scripts/transport/routes.lua`. If the wiki changes, edit that file.

Type `wt` to list all aliases. In the alias editor of Mudlet, the aliases are in the group `retromud-gui` / `world-transport`. This group is separate from your own aliases, so the names never clash.

| Alias | Walks to | Start here |
|---|---|---|
| `wt shaft <0-9>` | a Crypt shaft | Ngate Igneous, the north gate of Igneous City on Crypt |
| `wt ship <name>` | a Wysoom ship | Sgate Sauronan, the south gate of Sauronan on Wysoom |
| `wt key <name>` | an exit near Keystone | Ngate Keystone, the north entrance to Keystone |
| `wt pod <name>` | a Sosel pod | Wgate Edon, the west gate of Edon on Sosel |
| `wt grove <name>` | the same Sosel pods | the secluded grove, the exit of the Druid guild to the jungle on Sosel |
| `wt gate <name>` | a Perdow gate | the Quest Shrine in the SW corner of Perdow |

These names work with the aliases:

- ship: `bar` Barrier Island, `esh` Eastern Shore, `lag` Lagoon, `nep` Northeast Point, `swa` Swamp, `toh` Tohunga Island, `tro` Tropical Island, `val` Valley of Dreams, `wcl` Western Cliffs, `wsh` Western Shore.
- key: `aba` Abarack, `alt` Altar/Forest, `bio` Biomancer, `gyd` Gydnia, `key` Keystone, `pal` Paladin, `tem` Templar.
- pod and grove: the world that you want to reach. The names are `welstar`, `perdow`, `wysoom`, `crypt`, and `raji`.
- gate: `crypt`, `perdow`, `raji`, `sosel`, `welstar`, `wysoom`, `castle`, `cave`, and `pocket`.

The walks send one command for each step. A blocked step (for example a door or a monster) does not stop the rest of the walk.

These exits have no alias:

- The exits of Raji. They move around inside the Rift.
- The daily list of which shaft, ship and statue lead where. It changes at each boot. See the wiki.
- The Welstar statues.
- The Crypt shafts A to G. The wiki has no walk for them.

## License

[MIT](LICENSE). The pixel art in `src/resources/themes/` was generated with Runware for this project.
