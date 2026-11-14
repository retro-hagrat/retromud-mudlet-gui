# Survey of existing Mudlet GUI packages

Date of research: 2026-11-14. A subagent read seven packages from packages.mudlet.org. It read the source code of only two of them, because most packages have no source link. For the other packages, it unzipped the built `.mpackage` file and read `config.lua` and the XML. It did not run any package code.

Licenses: only ThresholdUI (0BSD) and LotJ UI (Apache-2.0) have a license that we could find. For all other packages, no license was found. We read them for ideas only. We must not copy their code.

## Packages

1. mudlet-base-ui 1.9.4 (Mudlet Makers). Source: https://packages.mudlet.org/packages/mudlet-base-ui. No repository and no license found. It is the best match for us, because it parses prompts when the MUD has no GMCP or MSDP.
2. ThresholdUI 4.6.1 (gesslar). Source: https://github.com/gesslar/ThresholdUI. License 0BSD. It has the cleanest Muddler layout and the cleanest install and uninstall code. It uses GMCP for data.
3. LotJ Mudlet UI 2.5.3. Source: https://github.com/LotJ/lotj-mudlet-ui. License Apache-2.0. It uses one folder for each feature. It ships its own mapper. The subagent did not read its install and uninstall code.
4. MedUI 1.9.1 (Kymbahl). No repository and no license found. It has flaws, but it teaches two things (see "Lessons").
5. GUIFlex 1.2 (Akaya). No repository and no license found. It is a small template with nine `Adjustable.Container`s. It has no cleanup code.
6. Merentha UI 2.9.10 (ealanta). No repository and no license found. The subagent found no uninstall handling, but it did not read the whole package.
7. Realms of Despair UI (skace, 2020). No repository and no license found. It is old. It has no uninstall handler and no saved settings.

The subagent did not find a package that uses only prompt triggers, except the fallback in mudlet-base-ui. Most authors assume that the MUD supports GMCP or MSDP. RetroMUD does not.

## Lessons

### Install and uninstall

1. Geyser objects, temporary triggers, timers, and anonymous event handlers belong to the profile, not to the package. They stay alive after the user uninstalls the package. The uninstall handler must remove each one.
2. Guard every handler with a check of the package name: `if pkg ~= AppName then return end`. Both ThresholdUI and mudlet-base-ui do this.
3. Use named event handlers and named timers. Then one call can remove all of them. ThresholdUI calls `deleteAllNamedEventHandlers(AppName)` and `deleteAllNamedTimers(AppName)`.
4. Save the old border size with `getBorderBottom()` (or the matching call for the other sides). Restore it on uninstall. MedUI does this. ThresholdUI sets the border to 0, which is worse. Our skeleton also sets it to 0, so we must change it.
5. If the user installs the package during a session, the startup events have already happened. Read the current state and apply it.

### Layout and saved settings

1. mudlet-base-ui creates its `Adjustable.Container` with `autoSave=false` and `autoLoad=false`. It saves one small settings table itself with `table.save` and `table.load` in `getMudletHomeDir()`. It wraps both calls in `pcall`.
2. mudlet-base-ui makes the `Geyser.Mapper` only after map data exists. Before that, a placeholder holds the space. An embedded mapper without a map shows a clipped widget.
3. MedUI calculates the border size again on `sysWindowResizeEvent`.

### Prompt parsing

All points in this list come from mudlet-base-ui.

1. Keep a table of labels for each stat (hp, mana, moves, xp). Build the regular expressions from the table.
2. Reject lines that look like chat, for example "I am on 100/120 hp".
3. Drop readings that make no sense, for example a maximum of 0.
4. Ignore a line that you already handled. Compare `getLineNumber()` values.
5. If a prompt shows only the current value, do not guess the maximum. Take the maximum from the `score` screen.
6. Trust a score screen only for a short time after the user really sent the `score` command.
7. MedUI changed from prompt parsing to GMCP and noted that prompt regexes broke on special prompts (blind, plague, poison). Plan for prompt variants.

### Mapper

1. MedUI uses `generic_mapper` and guards its code with `if map then`. It turns off a trigger of `generic_mapper` by its display name. This is fragile.
2. LotJ ships its own mapper. Its README tells the user to uninstall `generic_mapper`.
3. Our mapper is a separate package, so we need only events and the `getPackageInfo` check.

### Muddler files

1. ThresholdUI and LotJ use `"outputFile": true` in the `mfile` and one folder for each feature under `src/scripts`.
2. ThresholdUI has a GitHub Actions workflow that builds the release. We can copy the idea.
3. ThresholdUI sets `"dependencies": ""` in the `mfile`. It installs its own dependency at run time.

## How package dependencies work

Confirmed:

1. Muddler copies the `dependencies` string from the `mfile` into `config.lua` as `dependencies = [[...]]`. Source: `src/main/groovy/muddler/App.groovy` in https://github.com/demonnic/muddler.
2. The Mudlet Package Exporter writes the same key. It joins the names with commas. The label in the dialog is "Needs these packages". Source: `src/dlgPackageExporter.cpp` in https://github.com/Mudlet/Mudlet.

Not confirmed:

1. The subagent found no code in `Host.cpp` that reads the `dependencies` key. Mudlet may not install the listed packages by itself.
2. The subagent did not read the code of `mpkg`. We do not know if `mpkg` installs dependencies.

None of the packages that we read depends on automatic installation. We will list the mapper in `dependencies` as a comma-separated string. We will also check for the mapper at run time and show a message if it is missing.

## Sources

- https://packages.mudlet.org/
- https://github.com/gesslar/ThresholdUI
- https://github.com/LotJ/lotj-mudlet-ui
- https://github.com/demonnic/muddler
- https://github.com/Mudlet/Mudlet
- https://github.com/Mudlet/mudlet-package-repository
