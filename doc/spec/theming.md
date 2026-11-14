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

1. The colours of the game text and the background of the text area of the main window. Mudlet has no function for this. The player sets these colours in Mudlet Preferences. Each preset can come with a note that names the matching Preferences values.
2. The 16 ANSI colours.

## 4. Requirements

THEME-001. A theme must be a Lua table with a fixed set of keys. Section 5 lists the keys.

THEME-002. The first version must ship exactly these five presets: `dark` (the default), `light`, `flame` (reds and oranges), `ocean` (deep blues, cyan, and aquamarine), and `forest` (greens). Appendix A lists the colours. A preset must use soft, rich colours and not pure primary colours.

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

THEME-014. Text must sit on a solid or semi-transparent background, also when the theme has an image. A background image must never make text unreadable. The player can lower the opacity of an image with the key `imageOpacity`.

THEME-019. Theming is on by default. The GUI applies the saved theme, or `dark` when no theme is saved. Map theming is on by default. The player can turn map theming off with a setting.

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
4. `images`: a table that maps a role to a file name, for example `statusbar`, `panel`, `button`, and `window`. A value of `nil` means no image. Each entry can have a `mode` of `stretch` (a `border-image` stylesheet, which keeps text on top) or `plain` (`setBackgroundImage`, which draws the image at its own size and no text).
5. `imageOpacity`: a number from 0 to 1.
6. `cmdline`: a table with `background` and `text`. The module uses it only when the player turns it on.

Each role gets its stylesheet from a pure function. The function takes the theme and the role and returns a string. Tests can check this function without Mudlet.

## 6. Names of the files that the player can add

The player puts these PNG files in the theme folder. The names are a first proposal.

| File | Role |
|---|---|
| `window.png` | The background of the sidebar column |
| `statusbar.png` | The status bar |
| `panel.png` | The panels |
| `button.png` | The buttons |
| `tab.png` | The tabs of the chat panel |

An image that needs text uses the mode `stretch`. A file of the player is always used with the mode of its role.

## 7. The apply function

The function `rmgui.theme.apply(name)` does these steps in order:

1. Find the preset with this name. If it does not exist, show a message and stop. The old theme stays.
2. Merge the override file over the preset (THEME-010).
3. Check the merged theme. A key that is missing gets the value of the `dark` preset. A value of the wrong type is replaced in the same way, and the module shows one message.
4. Find the image for each role. The theme folder comes first. Then comes the folder of the preset. If no file exists, the role has no image (THEME-008).
5. Call the function of each registered element, inside `pcall` (THEME-007). The function receives the merged theme and the image paths. It calls the style setters again (THEME-005).
6. If map theming is on, save the old map colours when this is the first apply, and set the map colours (THEME-015).
7. If the player turned on the command line, set its stylesheet (THEME-016).
8. Save the name of the theme in the settings file (THEME-011).
9. Raise `rmgui.onTheme` (THEME-017).

An element registers itself in its `init()` with `rmgui.theme.register(name, fn)`. It removes itself in its `teardown()`. This keeps a new module free of special code in the theme module.

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

1. Do we add a `high-contrast` preset later? The five presets all pass 4.5 to 1 for text. A preset with 7 to 1 would help players with low vision.
2. Do we want a second dark and a second light preset later, for players who like variety?
3. What are the right names and sizes of the files in section 6? We need to test image sizes and memory use.
4. Do spaces in the path of an image work in `border-image`? We did not test this.
5. Does `changeMenuStyle("light")` of an `Adjustable.Container` match our light preset? We did not look at the result.
6. Is `rgui` a good alias prefix?

## Appendix A: the five presets

The colours are `r,g,b`. The player can change any of them in the override file. All colours were chosen to look soft and rich. None is a pure primary colour.

- `dark`: a blue-grey slate, not pure black, with an indigo accent.
- `light`: warm paper with deep ink text and a royal indigo accent.
- `flame`: charred brown-black with cream text and an ember orange accent. State colours stay warm: coral red, amber, and gold.
- `ocean`: deep navy with an aquamarine accent. The gauges use coral, azure, and aqua.
- `forest`: deep green-black with a fresh leaf-green accent.

| Token | `dark` | `light` | `flame` | `ocean` | `forest` |
|---|---|---|---|---|---|
| `surface` | 24,27,33 | 248,247,244 | 32,18,16 | 10,26,44 | 16,30,22 |
| `surfaceAlt` | 34,38,46 | 236,233,226 | 52,28,22 | 16,42,66 | 26,48,36 |
| `text` | 226,230,236 | 36,40,48 | 252,236,224 | 222,240,248 | 226,238,226 |
| `textMuted` | 150,158,170 | 96,102,112 | 206,160,140 | 140,176,196 | 150,176,152 |
| `accent` | 129,140,248 | 66,84,214 | 255,138,61 | 102,235,200 | 140,214,110 |
| `border` | 58,64,76 | 206,201,190 | 112,52,38 | 30,78,110 | 44,78,56 |
| `good` | 74,200,140 | 28,128,84 | 160,196,96 | 102,235,170 | 126,220,140 |
| `warn` | 240,185,80 | 160,100,0 | 255,196,64 | 250,208,100 | 236,190,90 |
| `danger` | 240,100,110 | 190,50,60 | 255,92,80 | 255,120,130 | 232,110,96 |
| `hp` | 240,100,110 | 190,50,60 | 255,92,80 | 255,120,130 | 232,110,96 |
| `sp` | 110,140,245 | 52,88,200 | 255,170,64 | 80,170,255 | 110,190,220 |
| `ep` | 92,200,160 | 24,124,96 | 255,214,102 | 90,230,210 | 150,220,120 |
| `map.background` | 16,18,22 | 240,238,232 | 24,12,10 | 6,18,32 | 10,22,14 |
| `map.exits` | 120,128,142 | 120,114,104 | 214,110,64 | 70,170,200 | 110,160,120 |

Contrast ratios, computed with the WCAG formula on 2026-11-14. Each cell is the lowest ratio in its group.

| Check | Limit | `dark` | `light` | `flame` | `ocean` | `forest` |
|---|---|---|---|---|---|---|
| `text` and `textMuted` on `surface` and `surfaceAlt` | 4.5 | 5.6 | 4.8 | 6.8 | 6.4 | 6.0 |
| `accent` on `surface` and `surfaceAlt` | 3 | 5.1 | 5.0 | 6.8 | 10.0 | 8.0 |
| `good`, `warn`, `danger`, `hp`, `sp`, `ep` on `surface` | 3 | 5.5 | 4.5 | 6.0 | 6.9 | 5.6 |
| `map.exits` on `map.background` | 3 | 4.7 | 4.1 | 5.6 | 7.0 | 6.1 |

All cells are at or above their limit.
