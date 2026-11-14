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

THEME-002. The GUI must ship at least these presets: `dark` (the default), `light`, and `high-contrast`. It can ship more, for example `amber` and `forest`.

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

THEME-013. The text of every preset must have enough contrast against its background: a ratio of at least 4.5 to 1 for normal text, and at least 7 to 1 in the `high-contrast` preset. Other parts of the GUI that carry meaning, such as borders of tabs and marks of unread lines, must reach 3 to 1. A test must compute these ratios for each preset. The test must fail when a preset is below the limit.

THEME-014. Text must sit on a solid or semi-transparent background, also when the theme has an image. A background image must never make text unreadable. The player can lower the opacity of an image with the key `imageOpacity`.

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

1. Should map theming be on by default? The map colours belong to the whole profile. The GUI can restore them, so on by default is acceptable. This is your decision.
2. Which presets do we ship in the first version? We propose `dark`, `light`, `high-contrast`, `amber`, and `forest`.
3. What are the right names and sizes of the files in section 6? We need to test image sizes and memory use.
4. Do spaces in the path of an image work in `border-image`? We did not test this.
5. Does `changeMenuStyle("light")` of an `Adjustable.Container` match our light preset? We did not look at the result.
6. Is `rgui` a good alias prefix?
