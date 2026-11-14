# Design: the frame layout

Status: draft, 2026-11-14.
Component: the `layout` module of `retromud-gui`. See `doc/design.md`, `doc/spec/theming.md`, and `doc/spec/chat.md`.

## 1. Purpose

The GUI frames the main text window with a status bar and two side columns. The frame holds the themed images, the chat, the map, the vitals, and the buttons. The main text window itself stays the normal Mudlet window.

## 2. What the research tells us

1. An image behind the main text window shows only in the gaps, because each piece of text has a black box. So the art must sit around the text window and not behind it. See `doc/research/theming.md`.
2. The border functions (`setBorderTop`, `setBorderLeft`, `setBorderRight`, `setBorderBottom`) reserve space around the main text window. Our labels fill that space.
3. The command line is a Mudlet widget at the bottom. The player wants nothing extra on it. So the frame does not touch it.
4. An `Adjustable.Container` can attach to a border and adjust the border by itself. The player can move and resize it. We can restyle its frame and title after it exists.
5. Pixel art images need a whole-number scale. At `imageScale` 2, a `panel` image has a 16 px frame and a `statusbar` image has an 8 px frame at the top and the bottom.

## 3. Terms

- Frame: the status bar and the two columns around the main text window.
- Column: a tall container at the left or the right edge. It holds panels.
- Panel: a framed box in a column. It uses the `panel` image.
- Wide layout: both columns are visible.
- Compact layout: the columns are hidden, and their panels open as floating windows.

## 4. The wide layout

```
+----------------------------------------------------------------------------+
| STATUS BAR   room, area, mapper state, theme menu         (statusbar image) |
+---------------+--------------------------------------+---------------------+
| CHAT COLUMN   |                                      | SIDE COLUMN         |
| (window tile  |                                      | (window tile        |
|  behind)      |      main text window                |  behind)            |
| +-----------+ |      (Mudlet, black text area)       | +-----------------+ |
| | tabs      | |                                      | | map (rmap.map)  | |
| |-----------| |                                      | +-----------------+ |
| | chat text | |                                      | | vitals gauges   | |
| |           | |                                      | +-----------------+ |
| +-----------+ |                                      | | buttons         | |
|               |                                      | +-----------------+ |
+---------------+--------------------------------------+---------------------+
| > command line (the Mudlet widget, nothing added)                          |
+----------------------------------------------------------------------------+
```

## 5. Elements

| Element | Owner | Image role | Notes |
|---|---|---|---|
| Status bar | `layout` | `statusbar` | Shows the room, the area (only while mapping), and the sync state. See "Status bar rules" in `doc/design.md` |
| Chat column background | `layout` | `window` | A tile that fills the column. The panels sit on it |
| Chat panel | `chat` | `panel`, `tab`, `tabActive` | A framed box with a tab strip and a miniconsole |
| Side column background | `layout` | `window` | The same tile |
| Map panel | the mapper | `panel` | The container `rmap.map` that the mapper creates. The GUI moves it here. See `doc/design.md` |
| Vitals panel | `vitals` | `panel` | The three gauges for hp, sp, and ep. Colours come from the theme |
| Buttons panel | `layout` | `panel`, `button` | The buttons call the mapper API |

## 6. Sizes

All sizes are in pixels. The columns and the status bar are `Adjustable.Container` objects that attach to a border. The player can resize them.

| Part | Default | Limits |
|---|---|---|
| Status bar height | 36 | 32 to 48. The smallest height is 4 slice pixels at the top and the bottom, times the scale, plus text height |
| Chat column width | 22% of the window width | 260 to 400 |
| Side column width | 26% of the window width | 300 to 440 |
| Gap between panels | 4 | Fixed |
| Bottom border | 0 | The command line stays clean |

A panel must be at least 3 times the frame of its image in each direction, so that the middle repeats at least once. At scale 2, that is 48 px for `panel`.

## 7. Requirements

LAYOUT-001. The wide layout must have the status bar at the top, the chat column at the left, the side column at the right, and the main text window in the middle. The layout must not add anything to the bottom. The command line stays as Mudlet draws it.

LAYOUT-002. The containers must attach to their borders with `Adjustable.Container`. The borders must follow the size of the containers when the player resizes them.

LAYOUT-003. When the layout starts, it must save the old values of the four borders with `getBorderTop()`, `getBorderRight()`, `getBorderBottom()`, and `getBorderLeft()`. In `teardown()`, it must put them back. See "Install and uninstall" in `doc/design.md`.

LAYOUT-004. The main text window must keep at least 80 characters of width. The module must compute the width from the font size of the main window. If the window is too narrow for both columns at their minimum widths, the layout must switch to the compact layout.

LAYOUT-005. The compact layout must hide both columns and set their borders to 0. The status bar stays. The status bar must offer a menu that opens each panel (map, chat, vitals, and buttons) as a floating window. The panels keep their content and their theme.

LAYOUT-006. The module must listen for the event `sysWindowResizeEvent`. On each event, it must work out the layout again and apply it. It must wait until the resize stops, so that a drag does not apply the layout many times in a second.

LAYOUT-007. The player must be able to force a layout with `rgui layout wide`, `rgui layout compact`, and `rgui layout auto`. The default is `auto`. The module must save the choice in the settings file.

LAYOUT-008. Each element must register a style function with the theme module. See section 7 of `doc/spec/theming.md`. The layout module must also call `setBorderColor` with the `surface` colour of the theme, so that no black strip shows next to a themed column.

LAYOUT-009. The column background must use the `window` image, or the `surface` colour when the theme has no image. Panels must sit on it with a gap of 4 px.

LAYOUT-010. All objects must have names that start with `rmgui.layout.`. See "Namespaces and packages" in `doc/design.md`.

LAYOUT-011. `init()` must create all objects, and `teardown()` must remove them and restore the borders. A second call of `init()` must not create a second copy.

LAYOUT-012. The module must save the size of each container in the settings file and read it again at the start. The containers are created with `autoSave=false` and `autoLoad=false`. See "Saved settings" in `doc/design.md`.

LAYOUT-013. The module must not fail when the mapper is not installed. The map panel then shows a short text that says the mapper is missing and tells the player how to get it.

## 8. Order of creation

The module creates the objects in this order, so that panels sit on top of the backgrounds:

1. The two column backgrounds and the status bar.
2. The panels inside the columns.
3. The buttons and the labels inside the panels.

## 9. Verification

1. Unit tests in plain Lua, without Mudlet, for the size calculation: the column widths for a list of window widths, the limits, the 80 character rule, and the switch to the compact layout. The function must take the window width and the character width as arguments, and return the sizes.
2. Tests by hand in Mudlet:
   - the wide layout at 1920, 1366, and 1100 px.
   - the switch to compact below the limit, and back.
   - dragging a column edge with the mouse.
   - the borders after `teardown()`.
   - a swap of all six themes with the layout open.
   - the layout with the mapper missing.

## 10. Open questions

1. Which Mudlet function gives the width of a character in the main window? We think it is `calcFontSize("main")`. We did not test it.
2. Does a label that fills a border area receive mouse events correctly? We did not test it.
3. Is the compact threshold right, and is `auto` the right default?
4. Do the containers keep the right order when the player drags them? The theme and the borders must stay correct.
5. Does the gauge need its own image roles and stylesheet roles (front, back, text)? The theme code has no gauge role yet.
6. How wide is the status bar text at the smallest column width? We must check that the room name and the area do not overflow.
