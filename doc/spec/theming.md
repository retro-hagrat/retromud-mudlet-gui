# Design: themes

Status: draft, 2026-11-14.
Component: the `theme` module of `retromud-gui`. See `doc/design.md` and `doc/research/theming.md`.

## 1. Purpose

The GUI ships several colour schemes. The player can swap between them while Mudlet runs. A scheme can change colours and background images. A player who does not write code can add images and change single values.

## 2. Terms

- Theme: a Lua table that holds the colours, the font sizes, and the image names for all GUI elements.
- Preset: a theme that ships with the GUI.
- Token: a named colour or value in a theme, for example `surface` or `accent`.
- Role: the part of the GUI that a style belongs to, for example `statusbar`, `button`, or `tab`.
- Element: one GUI object that has a style, for example the status bar or the chat panel.
- Override file: a file that the player edits. It changes single values of the active theme.
- Theme folder: the folder `getMudletHomeDir() .. "/retromud-gui-theme/"`. It is outside the package folder, so that an uninstall does not delete it.

## 3. What a theme can and cannot change

It can change:

1. The colours, borders, fonts, and images of our labels, gauges, tabs, buttons, and containers.
2. The map background colour and the colour of the exit lines.
3. The command line, if the player turns this on.

It cannot change:

1. The colours of the game text and the background of the text area of the main window. An image behind the main window shows only in the gaps, because each piece of text keeps a black box (tested in Mudlet). The GUI does not set a main window image. It frames the text area with its own labels instead, which can show images (see `window.png`). Mudlet has no function for this. The player sets these colours in Mudlet Preferences. Each preset can come with a note that names the matching Preferences values.
2. The 16 ANSI colours.

## 4. Requirements

THEME-001. A theme must be a Lua table with a fixed set of keys. Section 5 lists the keys.

THEME-002. The first version must ship exactly one preset for each of the six planets of the Retroverse: `welstar` (light, paladin), `crypt` (dark, vampire), `sosel` (red volcano, dinosaurs), `wysoom` (blue ocean, sharkmen), `raji` (air, djinn), and `perdow` (darkness, carnivorous plants). The planet style guide in `retroai/docs/rules/rules-planet-style.md` is the source of the looks. Appendix A lists the colours. A preset must use soft, rich colours and not pure primary colours.

THEME-003. A module must not contain a colour, a font name, or an image path. A module asks the theme module for the style of its role.

THEME-004. The player must be able to swap the active theme while Mudlet runs. A swap must not need a restart.

THEME-005. The function that applies a theme must call every style setter again, also when a value did not change. This includes `setBackgroundImage` with the same path. Mudlet loads an image file again only when the code calls `setBackgroundImage` again.

THEME-006. The apply function must be safe to call many times. It must give the same result each time.

THEME-007. An element that fails while it applies a theme must not stop the other elements. The apply function must run each element in `pcall`. It must show one short message for each failed element.

THEME-008. A missing, unreadable, or invalid image must not stop the apply function. The element must go without the image. The GUI must show one message for each file, and not repeat it.

THEME-009. The player must be able to put image files in the theme folder, with fixed names. A file in the theme folder wins over the image of the preset. Section 6 lists the names.

THEME-010. The player must be able to change single values in an override file. The file must replace values of the active theme key by key. An unknown key, or a value of the wrong type, must be ignored. The rest of the file must still apply.

THEME-011. The module must save the name of the active theme in the settings file. The module must apply it again when the profile loads.

THEME-012. The GUI must offer these commands: `rgui theme` (shows the active theme and the list of themes), `rgui theme <name>` (applies a theme), and `rgui theme reload` (reads the theme folder and the override file again and applies the active theme).

THEME-013. Every preset must have enough contrast. The ratio uses the WCAG formula for relative luminance. The ratio of `text` and of `textMuted` against `surface` and against `surfaceAlt` must be at least 4.5 to 1. The ratio of `accent`, of `good`, `warn`, `danger`, `hp`, `sp`, and `ep` against `surface`, and of the exit lines against the map background must be at least 3 to 1. The colour `border` is decoration and has no limit. A test must compute these ratios for each preset and for the merged theme of a player. The test must fail when a ratio is below its limit.

THEME-014. The presets ship without images. An image of the player replaces the background of its role, and the text sits directly on it. The module does not check images. The file `README.txt` in the theme folder must tell the player that an image must keep the text readable. A later version can put a half-transparent layer over an image. See section 5.

THEME-019. Theming is on by default. The GUI applies the saved theme, or `perdow` when no theme is saved. `perdow` is the home world of the game. Map theming is on by default. The player can turn map theming off with a setting.

THEME-015. When the GUI changes the map colours, it must first save the old values with `getMapBackgroundColor()` and `getMapRoomExitsColor()`. It must put them back when the package is uninstalled and when the player turns map theming off.

THEME-016. The GUI must not change the command line unless the player turns this on with a setting. Mudlet has no function that reads the old command line style, so the GUI cannot restore it exactly. The setting must say that an uninstall resets the command line to the Mudlet default.

THEME-017. The module must raise the event `rmgui.onTheme` after each successful apply. The argument is the name of the theme.

THEME-018. The module must clear all of its state in `teardown()`. This includes its event handlers and its list of elements. See "Namespaces and packages" in `doc/design.md`.

## 5. The theme table

A theme has these groups of keys. The names are a first proposal.

1. `name`, `title`, and `description`: for the list of themes.
2. `colors`: the tokens. Each token is `{r, g, b}` or `{r, g, b, a}`.
   - `surface`: the main background of panels.
   - `surfaceAlt`: a second background, for example for the title bar and the tabs.
   - `text`: the normal text colour.
   - `textMuted`: the text colour of less important text.
   - `accent`: the colour of the active tab, of focus, and of links.
   - `border`: the colour of borders.
   - `good`, `warn`, and `danger`: colours for state, for example the gauges and the mapper state.
   - `hp`, `sp`, `ep`: the colours of the three gauges.
   - `map`: a table with `background` and `exits`.
3. `fonts`: `family` (can be empty to use the default), `size` for normal text, and `sizeSmall`.
4. `images`: a table that maps a role to a file name, or to `false` for no image. The roles are `window`, `statusbar`, `panel`, `button`, `tab`, and `tabActive`. Section 6 describes how an image is drawn.
5. `imageScale`: a whole number of 1 or more, 1 by default. It is the factor by which an image is shown larger than its pixels. It keeps pixel art sharp.
6. `imageOpacity` is not in the first version. Qt stylesheets have no opacity, and the research did not find one for a label. A player who wants a softer image edits the image. A later version can put a half-transparent layer over the image.
7. `cmdline`: a table with `background` and `text`. The module uses it only when the player turns it on.

Each role gets its stylesheet from a pure function. The function takes the theme and the role and returns a string. Tests can check this function without Mudlet.

## 6. Images: names, sizes, and how they are drawn

The player puts PNG files with these names in the theme folder. The presets ship the same files in `themes/<theme name>/`. The names are a first proposal.

The art is pixel art. A plain stretch smears it, which we saw in Mudlet. So every image except the window tile is a nine-slice image. The four corners keep their pixels and are shown at `imageScale` times their size. The edges and the middle repeat. The stylesheet is `border-image: url("<file>") <slices> repeat repeat;` with a `border-width` of the slices times `imageScale`. We use `repeat` and not `round`, because `round` scales the tiles with smoothing and draws dark seam lines across a panel (seen in Mudlet).

| File | Role | Art size (px) | Slice (px): top, right, bottom, left | Drawn as |
|---|---|---|---|---|
| `window.png` | The column background | 128 x 128 | none | A tile at its own size. Qt cannot scale a tile |
| `panel.png` | The panels | 64 x 64 | 16, 16, 16, 16 | Nine-slice |
| `statusbar.png` | The status bar | 64 x 32 | 8, 16, 8, 16 | Nine-slice |
| `button.png` | The buttons | 48 x 48 | 12, 12, 12, 12 | Nine-slice |
| `tab.png` | An inactive tab | 48 x 48 | 12, 12, 12, 12 | Nine-slice. Built from `button.png`, so it has the same patterned edges |
| `tabActive.png` | The active tab | 48 x 48 | 12, 12, 12, 12 | Nine-slice. Built from `button.png` with the lighter text area and the accent line |

At the default `imageScale` of 1, the frame of a panel is 16 px on the screen. A frame at the size of 32 art pixels was too small: the test image turned into a blur, so the art uses four times the pixels.

Rules for the art:

1. The four corners must match. The generator mirrors the image to make sure of this.
2. The text area, which is the middle inside the slices, must be one flat colour of the theme. The generator paints it. The model does not keep a middle plain, even when the prompt asks for it.
3. The window tile is mixed with the `surface` colour of the theme, so that it stays quiet behind the panels.
4. The palette has at most 16 colours.
5. The window tile must have no seam. The generator builds it from one mirrored quadrant.
6. The tabs are built from the button art, not generated. The player liked the patterned bottom of the button best, so a tab has the same edges. `tab.png` is the button. `tabActive.png` is the button with the `surface` colour in the text area and a 2 pixel line of the `accent` colour on its top edge. The tab strip is 40 px high, the same as a button.
7. A button with an image has no hover look. A later version can ship a second image for it.

THEME-020. Every image that ships with a preset and carries text (every role except `window`) must have a flat text area that is the `surface` or `surfaceAlt` colour of its theme. Then the text contrast of section THEME-013 holds by construction. The generator reports the lowest text contrast for each image as a check. The module does not check the images of a player.

## 7. The apply function

The function `rmgui.theme.apply(name)` does these steps in order:

1. Find the preset with this name. If it does not exist, show a message and stop. The old theme stays.
2. Merge the override file over the preset (THEME-010).
3. Check the merged theme. A key that is missing gets the value of the default theme (`perdow`). A value of the wrong type is replaced in the same way, and the module shows one message.
4. Find the image for each role. The theme folder comes first. Then comes the folder of the preset. If no file exists, the role has no image (THEME-008).
5. Call the function of each registered element, inside `pcall` (THEME-007). The function receives the merged theme and the image paths. It calls the style setters again (THEME-005). A label ignores the `color:` of its stylesheet for text that it shows with `echo`. So the element must pass the colour from `rmgui.theme.textColor(role, theme)` to `label:echo(text, colour)`.
6. If map theming is on, save the old map colours when this is the first apply, and set the map colours (THEME-015).
7. If the player turned on the command line, set its stylesheet (THEME-016).
8. Save the name of the theme in the settings file (THEME-011).
9. Raise `rmgui.onTheme` (THEME-017).

An element registers itself in its `init()` with `rmgui.theme.register(name, fn)`. It removes itself in its `teardown()`. This keeps a new module free of special code in the theme module.

## 7a. Making the preset images

The script `tools/theme-art/generate.py` makes the images with the Runware image API. It needs the key in the environment variable `RUNWARE_API_KEY`. It does these steps for each theme and role:

1. It builds a prompt from a shared pixel-art style, the hex colours of the preset (read from `presets.lua`), the motif of the planet, and the role text from section 6.
2. It asks Runware for the image at a large size (a multiple of 64) and keeps the raw file in `tmp/theme-art-raw/`.
3. It shrinks the image to the art size with box averaging, cuts the palette to 16 colours, and mirrors it so that the corners match. It builds the window tile from one quadrant.
4. It paints the text area of each frame with a flat theme colour, adds the accent line to the active tab, and mixes the window tile with the `surface` colour.
5. It reports the lowest text contrast (THEME-020) and warns below 4.5 to 1.

The option `--from-raw` repeats steps 3 to 5 from the saved downloads and needs no API call. The option `--derive-tabs` rebuilds `tab.png` and `tabActive.png` from `button.png`. A button run also rebuilds them. The script `tools/theme-art/derive_panel.py <theme>` builds a panel from the status bar of a theme: the top band is the top edge, it is rotated for the left edge and mirrored for the right and bottom edges, and the end cap is the corner. We use it for `raji` so that the panel and the heading match. The script runs in about 30 seconds for all 36 images.

The command `generate.py --dry-run` prints the prompts, and `--selftest` checks the cleanup without the network. The options `--theme`, `--role`, and `--seed` make one image again.

The motifs follow the planet style guide:

| Theme | Motif |
|---|---|
| `welstar` | White marble and gold trim, paladin heraldry with shields, swords and laurel wreaths, fluted columns |
| `crypt` | Vampire crypt, black-violet stone and bone, blood crimson accents, small bats and fangs, stalactite arches |
| `sosel` | Volcano and jungle, black basalt with glowing lava cracks, dinosaur claw and scale patterns, fern leaves |
| `wysoom` | Deep ocean, coral and polished shells, shark fins and shark teeth, rolling waves |
| `raji` | Sky and djinn, Arabian arches and filigree, drifting clouds and stars, lamp and smoke swirls, gold trim |

The `sosel` button is a hand-made combination: the volcano top (and sides) of a generated image (seed 102) and the green fern bottom band of an earlier image (seed 72). The player chose the green jungle bottom over an orange thorn bottom. The player asked for a volcano on top and jungle at the bottom. The image file is the source of truth, because it cannot be rebuilt from one run of the script. The tabs of `sosel` follow from it with `--derive-tabs`.

The `raji` status bar has its own role text in the script (`ROLE_OVERRIDE`): ornate Arabian brocade in gold thread on deep indigo, with the pattern in the top band, the bottom band, and the end caps. The player chose seed 42 out of four. Any other image can get an override in the same way.
| `perdow` | Darkness and carnivorous plants, thorny vines, venus flytrap jaws, pitcher plants with dripping toxic green, crimson flower maws |

## 8. Look of an `Adjustable.Container`

The apply function restyles a container through its inner labels: `adjLabel`, `minimizeLabel`, and `exitLabel`. It uses `setTitle` for the title. The research showed that this works. These labels are not part of the documented interface, so every call needs `pcall`, and a test in Mudlet must fail when a field is missing. See `doc/research/theming.md`.

## 9. Presets from separate packages (later)

A theme can be a separate package. The package holds a `theme.lua` file and its images. The GUI looks for packages with names that start with `rmgui-theme-` in `getPackages()`, and it reads `theme.lua` from `getMudletHomeDir() .. "/<package name>"`. It looks again when it gets the event `sysInstallPackage`. We have not tested this. The first version ships all presets inside the main package.

## 10. Verification

1. Unit tests in plain Lua, without Mudlet:
   - merging the override file, including unknown keys and wrong types.
   - the function that builds a stylesheet for each role.
   - the contrast ratio of each preset (THEME-013).
   - the image lookup order, with a fake file check.
2. Tests by hand in Mudlet: swapping between all presets, a missing image, a changed image (THEME-005), restoring the map colours on uninstall (THEME-015), and the container fields (section 8).

## 11. Open questions

1. Do we add a `high-contrast` preset later? The six presets all pass 4.5 to 1 for text. A preset with 7 to 1 would help players with low vision.
2. Do we want more presets later, for example a plain neutral dark and light pair for players who do not want a planet look?
3. What are the right names and sizes of the files in section 6? We need to test image sizes and memory use.
4. Do spaces in the path of an image work in `border-image`? We did not test this.
5. Does `changeMenuStyle("light")` of an `Adjustable.Container` match the `welstar` preset? We did not look at the result.
6. Is `rgui` a good alias prefix?
7. Answered in Mudlet for `imageScale` 1: the stylesheet that the code builds shows crisp frames and flat text areas for all roles of `perdow` and `welstar`. Scale 2 and 3 are not tested.
8. Answered in Mudlet: `background-repeat: repeat` tiles the window image without a seam.
9. The images came out as pixel art after the cleanup, and the player has not judged them yet. The frames of `wysoom` (pink coral) and `raji` (sunset pink) use colours that differ from their palettes. Do we re-roll with another seed, or recolour the images to the palette?

## Appendix A: the six presets

The colours are `r,g,b`. The player can change any of them in the override file. All colours were chosen to look soft and rich. None is a pure primary colour. Each preset follows the style guide of its planet.

- `welstar` (law, paladin): white marble and warm stone, deep navy ink, royal blue accent, and gold borders. The only light preset.
- `crypt` (earth, vampire): black-violet stone with bone-coloured text and a blood crimson accent.
- `sosel` (fire, volcano, dinosaurs): basalt brown-black with lava orange and red, and jungle green for good states.
- `wysoom` (water, sharkmen): deep sea navy with a cyan accent. The gauges use coral, azure, and aqua.
- `raji` (air, djinn): twilight indigo with djinn gold and turquoise.
- `perdow` (chaos, carnivorous plants, darkness): near-black green with a toxic green accent and crimson flower red. This is the default.

| Token | `welstar` | `crypt` | `sosel` | `wysoom` | `raji` | `perdow` |
|---|---|---|---|---|---|---|
| `surface` | 247,246,241 | 20,18,24 | 30,18,14 | 8,24,46 | 30,28,58 | 10,16,14 |
| `surfaceAlt` | 234,231,221 | 32,27,36 | 50,28,20 | 14,40,72 | 44,40,82 | 18,30,24 |
| `text` | 30,34,46 | 236,228,220 | 250,236,222 | 222,240,250 | 240,236,250 | 222,236,226 |
| `textMuted` | 88,94,108 | 170,158,156 | 212,166,140 | 140,176,200 | 178,170,214 | 150,176,156 |
| `accent` | 40,72,168 | 214,64,92 | 255,104,56 | 64,196,230 | 240,190,80 | 150,224,70 |
| `border` | 190,160,86 | 84,44,56 | 120,46,28 | 28,74,116 | 96,84,150 | 40,70,40 |
| `good` | 24,120,80 | 120,190,150 | 140,200,96 | 96,224,176 | 110,214,190 | 110,214,140 |
| `warn` | 150,96,0 | 226,184,96 | 255,196,72 | 250,208,104 | 255,204,96 | 236,190,84 |
| `danger` | 178,40,52 | 240,96,104 | 255,96,92 | 255,122,132 | 255,128,150 | 232,84,120 |
| `hp` | 178,40,52 | 236,84,100 | 255,96,92 | 255,122,132 | 255,128,150 | 232,84,120 |
| `sp` | 44,84,184 | 140,150,230 | 255,176,64 | 92,170,255 | 130,170,255 | 140,150,240 |
| `ep` | 18,118,96 | 150,200,170 | 140,204,100 | 96,224,200 | 110,214,190 | 150,224,70 |
| `map.background` | 238,235,226 | 14,12,18 | 22,12,10 | 5,16,34 | 22,20,46 | 6,10,8 |
| `map.exits` | 112,100,76 | 160,140,140 | 230,120,70 | 72,160,208 | 150,140,210 | 110,150,100 |

Contrast ratios, computed with the WCAG formula on 2026-11-14. Each cell is the lowest ratio in its group.

| Check | Limit | `welstar` | `crypt` | `sosel` | `wysoom` | `raji` | `perdow` |
|---|---|---|---|---|---|---|---|
| `text` and `textMuted` on `surface` and `surfaceAlt` | 4.5 | 5.3 | 6.5 | 7.3 | 6.5 | 6.3 | 7.3 |
| `accent` on `surface` and `surfaceAlt` | 3 | 6.6 | 3.8 | 5.6 | 7.2 | 8.0 | 10.7 |
| `good`, `warn`, `danger`, `hp`, `sp`, `ep` on `surface` | 3 | 4.9 | 5.3 | 6.2 | 7.1 | 6.8 | 5.5 |
| `map.exits` on `map.background` | 3 | 4.9 | 6.1 | 6.5 | 6.5 | 5.9 | 5.9 |

All cells are at or above their limit.

## Appendix B: the theme picker

The player can change the theme in two ways: with the command `rgui theme <name>`, or with the picker.

1. A button at the right end of the status bar shows the title of the active theme and a down marker, for example `Perdow v`. The layout module reserves 144 px for it (the slot `picker`), and the status text is narrower by the same amount, so the text never runs under the button.
2. A click on the button opens a panel below the status bar, right-aligned to the window. The panel has six rows of 40 px, with 4 px gaps, one for each planet in the order of `rmgui.theme.list()`. Each row is drawn in its own theme, with that theme's button image and text colour, so the row is a preview. The row of the active theme says `(current)`.
3. A click on a row applies the theme through `rmgui.theme.command`, saves the choice in the settings file, and closes the panel. A click on the row of the active theme only closes the panel.
4. A transparent backdrop covers the main window while the panel is open, so a click anywhere else closes it. The panel also closes on a click on the button, on a layout change, and on a window resize.
5. The first time the GUI starts, it prints one line: `tip: click the theme button at the top right, or type rgui theme`. The settings key `ui.hintShown` records that the player has seen it.

Found in a live Mudlet: Mudlet raises `sysWindowResizeEvent` for every border change. The layout module must compare the new window size with the one it applied, or its own border change triggers the next resize event again.
