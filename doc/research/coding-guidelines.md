# Coding guidelines for the RetroMUD GUI

This document lists the coding guidelines that we found in Mudlet documentation and forum threads. It also says how each guideline applies to this package. Date of research: 2026-11-14.

## Scope and trust level

The sources are the Mudlet wiki and a Mudlet forum thread from 2020. We found no Reddit threads. The wiki is the most reliable source. The forum thread is old, so current Mudlet behavior can differ.

The results of a survey of other GUI packages are in `package-survey.md` in this folder. Where the survey adds to a guideline, this document says so.

## Terms

- Package: a zip file with the extension `.mpackage`. A user installs it in the Package Manager.
- Geyser: the Mudlet library that builds GUI elements in Lua.
- Event: a named message. One script raises it, and other scripts listen for it.
- GMCP: a data channel that some MUDs use to send game state. RetroMUD does not support it.
- Muddler: a community tool that builds an `.mpackage` from source files.

## Guidelines from the Mudlet wiki

These come from the Mudlet Best Practices page.

1. Keep all code and data in one table. Do not add names to the global namespace. All scripts in a Mudlet profile share one Lua environment, so another package can overwrite a global name.
2. Raise your own events, so that other scripts can listen for them. Then the order in which users install scripts does not matter.
3. Give every Geyser element a unique name. Mudlet reuses an existing label or miniconsole that has the same name.
4. Use percentages for sizes, so that the layout adapts to the window size.
5. Put groups of GUI elements in an `Adjustable.Container`. Then the user can move and resize them.
6. Undo all UI changes when the package is uninstalled. Reset the borders and hide the elements.
7. Package every font that you use.
8. Use `/` in file paths, not `\`. This also applies to Windows.

## Guidelines from the forum thread

The thread is "Package and module interdependence best practices" (forums.mudlet.org, t=22853, March 2020). The speakers are Mudlet maintainers.

1. Most authors include their dependencies inside their package. Others tell the user to install the other package. In 2020, Mudlet did not install dependencies by itself.
2. Use tables for namespacing and local variables wherever possible.
3. Duplicated code is not a big problem. One maintainer said that 5 kB of duplicated code in a profile is not an issue.
4. A package assumes that the user installs it once for each profile. Modules came later. They exist to share code between profiles.
5. Many users edit code inside Mudlet. We build from files, so this does not change our work flow. The built package must still work when the user opens it in the Mudlet editor.

## Guidelines from the search results

These sources were weaker. Some looked auto-generated. Treat them as hints and test them.

1. Match the prompt with one regular expression trigger. The trigger raises an event, and the gauge code listens for it. The trigger does not call the gauge code directly.
2. Update a gauge only when its value changed.

## How we apply the guidelines

1. The package keeps all state in the table `rmgui`. A new module adds a field to this table. It does not add a global name.
2. The GUI and the mapper talk only through events. The mapper raises `rm.onRoom`. The GUI listens for it. The GUI must work when the mapper is missing, and it must say so on screen.
3. The GUI detects the mapper with `getPackageInfo("retromud", "version")`. The call returns an empty string when the package is not installed.
4. Every GUI element has a unique name that starts with `rmgui.`.
5. Sizes use percentages, except for fixed bar heights.
6. Every group of elements lives in an `Adjustable.Container` with a name, so that Mudlet can save the layout.
7. The uninstall handler resets the borders, hides the elements, and removes every event handler. The skeleton already does this for the top bar.
8. Vitals come from the prompt. RetroMUD has no GMCP. The mapper finds the end of a prompt with the Mudlet function `isPrompt()`, because RetroMUD sends a GA/EOR signal after every prompt. The GUI uses the same method, and does not rely on a prompt pattern to find the prompt. The player can change the prompt format, so the vitals parser reads the values from the prompt line and raises an event, for example `rmgui.onVitals`. The default prompt has the form `Hp: 10/20 Sp: 5/9 Ep: 7/7`. See `docs/output-format.md` in the mapper repository.
9. We do not bundle the mapper at this time. The README tells the user to install the mapper package for map features.

## Open questions

These points are not confirmed. Check each one before you rely on it.

1. Does Mudlet install the packages that the `dependencies` field lists? The field exists. Muddler copies the `"dependencies"` string from the `mfile` into `config.lua`, and the Package Exporter writes a comma-separated list. The survey found no Mudlet code that installs them. Test this with a built package.
2. Which exact Muddler file layout does the current release expect? The `scripts.json` format in this repository comes from memory. The first run of `muddle` will show if it is correct.
3. Who owns the map pane? The mapper has its own pane. The GUI wants to host the map in its own container. We must decide this before we build the map container.
4. Which methods does `Adjustable.Container` have for saving the layout in a package? Read the Geyser API page before you write this code.

## Sources

- Mudlet Best Practices: https://wiki.mudlet.org/w/Manual:Best_Practices
- Mudlet Packages: https://wiki.mudlet.org/w/Manual:Mudlet_Packages
- Mudlet Geyser manual: https://wiki.mudlet.org/w/Manual:Geyser
- Package and module interdependence best practices: https://forums.mudlet.org/viewtopic.php?t=22853
- The Shared Namespace and You: https://forums.mudlet.org/viewtopic.php?t=1211
- Drag and Drop GUI Framework: https://forums.mudlet.org/viewtopic.php?t=22636
- Adjustable.Container API: https://cn.mudlet.org/geyser/files/geyser/Adjustable.Container.html
- Muddler releases: https://github.com/demonnic/muddler/releases
