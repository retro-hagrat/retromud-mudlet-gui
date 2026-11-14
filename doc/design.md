# Design: RetroMUD GUI

Status: draft, 2026-11-14. The mapper side of the contract is partly built. Items marked "proposed" do not exist yet.

## Goals

1. Give RetroMUD players a complete Mudlet GUI: status bar, vitals, chat, buttons, and a map.
2. Let players use the mapper without the GUI. The mapper must stay a full product on its own.
3. Ship one `.mpackage` file for the GUI, in `dist/` and on GitHub releases.

## Non-goals

- GMCP support. RetroMUD does not send GMCP.
- A copy of the mapper inside the GUI package.
- Automatic installation of the mapper. We could not confirm that Mudlet does this.

## The two packages

| Package | Repository | Owns |
|---|---|---|
| `retromud` | retromud-mudlet-mapper | Room detection, map data, speedwalking, and the map pane |
| `retromud-gui` | retromud-mudlet-gui | The status bar, vitals, chat, buttons, and the layout of the screen |

The user installs both. The GUI lists `retromud` in `dependencies`. The GUI must still work when the mapper is missing. In that case, the status bar says that the mapper is not installed.

The packages share no code and call no functions of each other. They talk only through events and through one named container.

## The map pane belongs to the mapper

The mapper creates the map pane. The GUI can move the pane into its layout. The GUI never creates or deletes it.

Reasons:

1. Players who want only the mapper still get a pane.
2. The mapper knows when map data exists. It creates the `Geyser.Mapper` widget only after that. An empty embedded mapper looks clipped.
3. Install order does not matter. No package must remove a pane that the other package made.

### Container contract (proposed)

1. The mapper creates an `Adjustable.Container` with the name `rm.map`. The `Geyser.Mapper` widget lives inside it.
2. By default the container floats and the user can move it.
3. The mapper raises the event `rm.onUiReady` with the container name as its argument, after it creates the container. It also raises the event again if it recreates the container.
4. The GUI listens for `rm.onUiReady`. When the event arrives, the GUI moves the container into its own layout. It must also check at start up whether the container already exists, because the mapper can load first.
5. The GUI moves the container with the Geyser method `changeContainer`. We did not verify that this method exists. Read the Geyser API before we write this code.
6. The mapper must not call `setBorder*` for `rm.map`. The GUI owns the screen borders when it is present. A mapper setting decides if the mapper docks to a border when it runs alone.
7. If the user uninstalls the GUI, the GUI gives the container back (floating) and does not delete it. If the user uninstalls the mapper, the GUI removes its own reference to the container and shows an empty slot.

### Version check (proposed)

The mapper stores its version in `rm.version` (for example `"0.0.3"`). The GUI reads `getPackageInfo("retromud", "version")`. The contract has its own number, `rm.uiContract`, starting at 1. The GUI shows a message if the number is missing or too low.

## Events

All events have the prefix `rm.` and come from the mapper. The GUI raises events with the prefix `rmgui.`.

| Event | Raised by | Arguments | Status |
|---|---|---|---|
| `rm.onRoom` | mapper | a table with `name`, `exits`, `lines`, `fingerprint` | exists |
| `rm.onSegment` | mapper | the number of real lines in the block | exists |
| `rm.onMoveFail` | mapper | none | exists |
| `rm.onUiReady` | mapper | the container name | proposed |
| `rm.onMoved` | mapper | the room id, the room name, and the area name, after the mapper resolved the position | proposed |
| `rm.onMapping` | mapper | `true` or `false`, raised by `rmap start` and `rmap stop` | proposed |
| `rm.onState` | mapper | the new sync state: `"SYNCED"`, `"PENDING"`, or `"UNSYNCED"` | proposed |
| `rmgui.onVitals` | GUI | a table with `hp`, `hpMax`, `sp`, `spMax`, `ep`, `epMax` | proposed |

Important detail: the mapper raises `rm.onRoom` when its capture code sees a room block. This happens before the mapper decides where the player is. So `rm.onRoom` means "a room was shown", and it does not mean "the map position changed". The status bar can use it at first. The proposed event `rm.onMoved` fixes this. The mapper raises it after the tracker resolves the block to a room.

Events tell the GUI that something changed. The GUI must not poll. To ask a question or to give a command, the GUI calls the API in the next section.

## Status bar rules (proposed)

The status bar shows the room name and the sync state. It also shows the area name, but only in this case:

1. Mapping is on. This means the player typed `rmap start`. The GUI learns this from `rm.onMapping`, and reads the start value with `rm.api.isMapping()`.
2. The sync state is `"SYNCED"` or `"PENDING"`. In `"UNSYNCED"` state the last area can be wrong, so the GUI hides it.

When the GUI hides the area, it also removes the gap. It does not leave an empty space in the bar. The room name stays visible when mapping is off, because it comes from the room text that the mapper captures.

Where the area name comes from: the mapper puts each room into an area (`areaId()` in `src/50_builder.lua`). The mapper adds the area name to `rm.onMoved` and to `rm.api.position()`. The GUI makes no Mudlet map calls of its own.

## Mapper API (proposed)

The mapper keeps its state in the global table `rm`. The public methods live in `rm.api`. Everything else in `rm` is private, and the GUI must not use it. In particular, the GUI must never write the map graph. Only the mapper's builder module does that.

### Rules

1. The GUI checks `rm and rm.api` before each call, and runs the call inside `pcall`. The mapper can be missing or old.
2. `rm.api.version` is a whole number that starts at 1. The GUI reads it at start up. If the number is lower than the number that the GUI needs, the GUI shows a message and does not call the API. We raise the number when we remove or change a method. Adding a method does not raise it.
3. A method does not raise an error in a normal case. On failure it returns `nil` and a reason string.
4. A command method runs the same code as the matching `rmap` alias. The alias and the method must behave the same.
5. A command that sends text to the game returns at once. The result arrives later, as an event.
6. The first version has no method that returns a table that the mapper also uses. Each method returns plain values.

### Questions

| Method | Returns | Backed by |
|---|---|---|
| `rm.api.state()` | `"SYNCED"`, `"PENDING"`, or `"UNSYNCED"` | `rm.track.state()` |
| `rm.api.position()` | the room id, the room name, and the area name, or `nil` when the state is `"UNSYNCED"` | `rm.track.pos` and the Mudlet functions `getRoomName`, `getRoomArea`, and `getRoomAreaName` (not verified) |
| `rm.api.isMapping()` | `true` or `false` | `rm.mapping` |
| `rm.api.busy()` | the name of the running job (for example `"speedwalk"`), or `nil` | `rm.job` |
| `rm.api.container()` | the name of the map container (`"rm.map"`), or `nil` when it does not exist | the map pane module |

### Commands

| Method | Same as | Result |
|---|---|---|
| `rm.api.start()` | `rmap start` | `true` |
| `rm.api.stop()` | `rmap stop` | `true` |
| `rm.api.where()` | `rmap where` | `true`, or `nil` and a reason when the mapper is busy |
| `rm.api.scan()` | `rmap scan` | `true`, or `nil` and a reason when the mapper is busy |
| `rm.api.undo()` | `rmap undo` | `true`, or `nil` and a reason when nothing can be undone |

The busy check for `where` and `scan` uses the existing guard `rm.canRun()`. This guard refuses the command while the mapper follows someone or runs another job.

### Not in the first version

1. `goto` a room. The mapper has no `rmap goto` command today. Add the command first, then the method.
2. Any method that changes settings, prompt patterns, or the map data.
3. Any method that returns the map graph, the tracker queue, or room fingerprints.

### Notes on the backing code

We read the mapper source on 2026-11-14. The commands `start`, `stop`, `where`, `scan`, and `undo` exist as `rm.commands.*` and print their result with `rm.out`. They return nothing today. The API methods must wrap them and return a value, or the commands must change. The mapper has no code yet that raises `rm.onMoved` or `rm.onState`. The tracker is the right place for both, because it owns the sync state.

## Vitals

1. The mapper finds the end of a prompt with `isPrompt()`. RetroMUD sends a GA/EOR signal after every prompt. The GUI uses the same method.
2. The player can change the prompt format. The default form is `Hp: 10/20 Sp: 5/9 Ep: 7/7`.
3. The vitals module reads the prompt line and raises `rmgui.onVitals`. It does not guess a maximum value when the prompt shows only the current value. It takes the maximum from the `score` screen.
4. The parser rejects lines that look like chat, rejects impossible values, and ignores a line that it already handled.
5. The parser is pure Lua, with no Geyser calls, so that we can test it offline.

## Namespaces and packages

### Packages

1. The project has two packages. `retromud` is the mapper. `retromud-gui` is the GUI. We keep the name `retromud` for the mapper, because a rename breaks existing installs.
2. The GUI lists `retromud` in `dependencies`. The two packages talk only through events and through `rm.api`.
3. We do not make a third package for shared code. The Mudlet maintainers say that a little duplicated code is not a problem. If both packages need the same small helper, each package keeps its own copy.

### Global names

1. All scripts in a Mudlet profile share one Lua environment. So each package owns exactly one global table. The mapper owns `rm`. The GUI owns `rmgui`. A package must not add any other global name.
2. The GUI never reads or changes `rm`, except through `rm.api`. The mapper never reads or changes `rmgui`.
3. Each module of the GUI is a sub-table of `rmgui`. Examples are `rmgui.core`, `rmgui.layout`, `rmgui.vitals`, `rmgui.chat`, `rmgui.theme`, and `rmgui.settings`. A part of a module is a sub-table of the module. The chat engine is `rmgui.chat.engine`. Its data is `rmgui.chat.rules`.
4. Events use the same prefixes. The mapper raises events that start with `rm.`. The GUI raises events that start with `rmgui.`.
5. Geyser objects, triggers, and timers have names that start with `rmgui.`. Mudlet reuses an object that has the same name, so a name must be unique.
6. A script that is not part of a package must not use the names `rm` or `rmgui`. We cannot enforce this. We can only choose names that are unlikely to clash.

### Files and modules

1. Each module is a folder in `src/scripts/`. This layout works with Muddler. Each folder has a `scripts.json` that lists its scripts in load order.
2. A module splits into pure files and glue files. A pure file has no Mudlet call and no Geyser call. Plain `lua` can run its tests. `rules.lua` and `engine.lua` of the chat module are pure files. A glue file creates triggers, Geyser objects, and event handlers. We test glue files by hand in Mudlet.
3. Each module exposes two functions: `init()` and `teardown()`. The function `init()` creates what the module needs. The function `teardown()` removes all of it. This includes Geyser objects, triggers, timers, event handlers, and border changes.
4. The `core` module calls `init()` of each module in a fixed order when the profile loads. It calls `teardown()` in the reverse order when the package is uninstalled. A new module needs only a new entry in the list of `core`.
5. The `core` folder is first in `src/scripts/scripts.json`, so that the `rmgui` table exists before any other module runs. Each file starts with `rmgui = rmgui or {}`, so that the tests can load a single file. We did not yet verify in Mudlet that scripts run in the order of the file.

### Limits

1. Another package that uses the global names `rm` or `rmgui` clashes with ours. We cannot prevent this.
2. The names `rm` and `rmgui` are short. A rename is cheap now and costly later. We keep them for now.

## Modules

Each module is a folder in `src/scripts/`. All state lives in the table `rmgui`.

| Module | Job |
|---|---|
| `core` | The `rmgui` table, install and uninstall handlers, saved settings |
| `layout` | Containers and borders. It saves the old border sizes and restores them on uninstall |
| `vitals` | The prompt parser and the vitals gauges |
| `chat` | The chat engine (pure Lua, done) and the chat panel (not started). See `doc/spec/chat.md` |
| `map-host` | Finds `rm.map` and moves it into the layout |
| `buttons` | The button bar |

Two modules exist today. `core` is in `src/scripts/core/gui.lua`. It contains the first status bar, and it does not yet follow the `init()` and `teardown()` pattern. `chat` holds the pure rule engine in `src/scripts/chat/`. We will split `core` when we add the other modules.

## Install and uninstall

1. Every event handler checks the package name: `if pkg ~= "retromud-gui" then return end`.
2. Geyser objects, temporary triggers, timers, and anonymous event handlers belong to the profile. They stay after an uninstall. The uninstall handler must remove all of them.
3. The GUI saves the old border sizes with `getBorderTop()` and the matching calls, and restores them on uninstall. The current code sets the top border to 0 and must change.
4. If the user installs the package during a session, the start up events already happened. The GUI reads the current state and applies it.

## Saved settings

The GUI creates its containers with `autoSave=false` and `autoLoad=false`. It saves one settings table with `table.save` in `getMudletHomeDir()`, and loads it with `table.load`. Both calls run inside `pcall`.

## Theming (proposed)

The GUI must be easy to customize, also for players who do not write code. A player can change colors, fonts, and images without editing Lua.

### Rules for our code

1. All styling comes from one theme table. No module contains a color, a font name, or an image path. The `layout` module reads the table and applies it.
2. The GUI ships a default theme and a few presets: dark, light, and high contrast.
3. Text always sits on a solid or semi-transparent background, so that an image cannot make it unreadable.
4. A theme can be applied again without a restart, so that the player sees a change at once.

### What the player can do

1. Put image files in the theme folder in the profile: `getMudletHomeDir() .. "/retromud-gui-theme/"`. The folder belongs to the player, so a reinstall of the package must not delete it. The GUI creates the folder on first run and writes a short `README.txt` into it.
2. Use fixed file names. If the folder holds `background.png`, `statusbar.png`, or `button.png`, the GUI uses that file for the matching element. If a file is missing, the GUI uses the default.
3. Change one value in a settings file, saved with `table.save`. The file overrides the default theme, key by key, for example a color or a font size.
4. Type `rgui theme <preset>` to switch presets, and `rgui theme reload` to read the folder and the settings file again.
5. Move and resize panels with the mouse. `Adjustable.Container` does this and saves the layout. This needs no theming.

### Fallbacks

1. A missing, unreadable, or invalid image is skipped. The GUI uses the default and prints one short message. It must not repeat the message.
2. An unknown key or a wrong type in the settings file is ignored for that key. The rest of the file still applies.

### Verified against the Mudlet manual (2026-11-14)

The pages are in the Sources list below. Items marked "summary" come from a tool summary of a page, not from the exact text. Check them again in Mudlet before we rely on them.

1. `Geyser.Label:setBackgroundImage(imageFileName)` sets an image on a label. Exact text.
2. `Geyser.MiniConsole:setBackgroundImage(imgPath, mode)` takes mode 1 (border), 2 (center), 3 (tile), or 4 (style). Exact text. The manual says that miniconsole images need Mudlet 4.10 or newer (summary).
3. The main window also takes `setBackgroundImage([windowname], imageLocation, [mode], [fullWindow])`, and `fullWindow` works on the main window only (summary).
4. `resetBackgroundImage()` exists on labels and miniconsoles. Exact text.
5. Label stylesheets support `background-color`, `border`, `border-radius`, `border-image: url(...)`, `background-image` with repeat and position, `rgba()` colors, and `QLabel::hover`. These appear in the manual's examples. The manual does not list `opacity`. Use `rgba()` for transparency, for example `background-color: rgba(0,0,0,0%)`.
6. Image paths are local file paths. The manual documents no URL support. Use `/` in paths, because `\` "has been known not to work". The manual says nothing about spaces in paths.
7. If the file cannot be read, the call returns `nil` and an error message. Check the return value.
8. A stylesheet with a background image also styles the label's tooltip. Wrap the rule in `QLabel{...}` to avoid this.
9. Label fonts use `setFont(font)` and `setFontSize(size)`, with the size in points. Sizes above 30 are probably too large. A miniconsole needs a font size, or it does not work properly.
10. `Adjustable.Container` has the constructor options `adjLabelstyle`, `menustyle`, `buttonstyle`, `buttonsize`, `titleTxtColor`, `titleFormat`, `lockStyle`, `defaultDir`, `autoSave`, and `autoLoad`. It has the methods `changeMenuStyle("dark" or "light")`, `save`, `load`, `saveAll`, and `loadAll`. The manual does not show the value format for the style options.
11. PNG and JPG work (summary). SVG works on labels in Mudlet 5.1 and newer (summary).

### Not confirmed

1. Where Mudlet puts the files from `src/resources/` after install, and whether an uninstall deletes them. An earlier read of the Packages page says they go to `getMudletHomeDir() .. "/<package name>"`. The theming page read did not confirm this. Test it with a built package. The player's images stay in the profile theme folder either way.
2. How to ship a TTF font and use it in a label.
3. How to give the frame, the title, or the buttons of an `Adjustable.Container` a custom image. The manual has a section "Change Adjustable Container Style" that we did not read yet. Read it before we design the container looks.
4. Background transparency for a miniconsole.
5. Memory use and caching of large images. Document a recommended maximum size after we test.
6. Spaces in image paths.
7. Whether Mudlet has an official theme mechanism. We found none. `Geyser.StyleSheet` is a managed stylesheet helper, and we did not read its page.

## Testing

1. `test/` holds a stub of the Mudlet functions, in the same way as the mapper repository.
2. The vitals parser has tests that use prompt lines from the mapper's `test/captures/`.
3. We test the layout code by hand in Mudlet.

## Open questions

1. Does `changeContainer` move an `Adjustable.Container` with its saved layout? Verify in Mudlet.
2. Does Mudlet install packages that `dependencies` lists? Test with a built package.
3. Where in the tracker does the mapper raise `rm.onMoved` and `rm.onState`? Define it with the mapper changes.
4. What does the vitals parser do for a prompt that has no Hp, Sp, or Ep values? Check `help prompt` in the game.

## Related documents

- Mudlet manual pages used for theming: https://wiki.mudlet.org/w/Manual:UI_Functions, https://wiki.mudlet.org/w/Manual:Geyser, https://www.mudlet.org/geyser/files/geyser/Geyser.Label.html, https://www.mudlet.org/geyser/files/geyser/Geyser.MiniConsole.html, https://www.mudlet.org/geyser/files/geyser/Adjustable.Container.html

- `doc/research/coding-guidelines.md`
- `doc/research/package-survey.md`
- The mapper repository: `docs/design.md`, `docs/output-format.md`
