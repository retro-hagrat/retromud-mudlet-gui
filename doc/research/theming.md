# Research: swapping themes in Mudlet

Date: 2026-11-14.
Method: we ran Lua in a live Mudlet 5.1.1 (Linux) with the Mudlet MCP server. The test profile was `RetroMUD2`. The player looked at the screen and sent screenshots, because Lua cannot read what is on the screen. We removed all test objects afterward.

## Question

Can the GUI ship several colour schemes and background images, and can the player swap between them while Mudlet runs? Can themes be separate packages?

## Summary

| Task | Result | Evidence |
|---|---|---|
| Change the colours of our labels | Easy | Tested, seen on screen |
| Change a background image on a label | Easy | Tested, seen on screen |
| Stretch an image over a label and keep text on top | Easy, with `border-image` | Tested, seen on screen |
| Restyle an `Adjustable.Container` after it exists | Easy, through its inner labels | Tested, seen on screen |
| Recolour the text area of the main window | Not possible | Tested. Only the empty space changes |
| Change the 16 ANSI colours from Lua | Not possible | No function found. No config key found |
| Ship a theme as a separate package | Likely easy | Parts tested. The whole path is not tested |
| Recolour the map background and the exit lines | Easy | Tested, seen on screen |
| Recolour the command line | Works with `setCmdLineStyleSheet` | Tested, seen on screen. We cannot read the old value back |
| Keep the images of a player after an uninstall | Only outside the package folder | Tested |

## Results

### 1. Live change of a label stylesheet

1. We created a `Geyser.Label` and gave it a red stylesheet. Then we called `setStyleSheet` again with a blue stylesheet.
2. The label changed from red to blue at once. `getLabelStyleSheet` returned the new text. The player saw the blue label with a yellow border.
3. A change that we scheduled with `tempTimer` did not run. This is a property of the MCP session. It does not affect the GUI.

### 2. Images on a label with `setBackgroundImage`

We used made-up PNG files of 96 by 48 pixels.

1. The image is drawn at its own size. It sits at the left side of the label. It is not stretched.
2. The image replaces the text of the label. We cannot put text over an image with this call.
3. A PNG with transparent pixels works. The label colour shows through the transparent part.
4. Calling `setBackgroundImage` again with another file changes the image at once.
5. If we overwrite the file on disk, the label does not change. Mudlet does not watch the file.
6. If we call `setBackgroundImage` again with the same path, the label shows the new file. So an apply function that calls it again always loads the current file.
7. A call with a path that does not exist returns `nil` and an error message. The message says that the label was not found or that the image could not be loaded.

### 3. Stretching an image over a label

The stylesheet `QLabel{border-image: url("<path>"); color: white;}` stretches the image over the whole label. The text of the label shows on top of the image. This is the right way to make a background that needs text.

### 4. Restyling an `Adjustable.Container`

1. The container keeps its parts as fields: `adjLabel` (the frame and the title), `minimizeLabel`, `exitLabel`, and others. Each is a `Geyser.Label`.
2. We called `setStyleSheet` on `adjLabel`, `minimizeLabel`, and `exitLabel` after the container existed. The frame turned dark green with a gold border. The two buttons turned gold and red.
3. `setTitle("text", "yellow")` changed the title and its colour.
4. The field `minLabel` is not the visible minimize button. `minimizeLabel` is.
5. These fields are not in the documented interface. A new Mudlet version can rename them. Our code must guard each call with `pcall`.
6. We called `changeMenuStyle("light")`, and the call did not fail. We did not look at the menu, so we do not know the result.

### 5. The main window and the ANSI colours

1. `setBackgroundColor("main", r, g, b, a)` changes only the empty space of the main window. Each piece of game text keeps its own black background. So the text area stays black.
2. `getConfig()` returns 65 settings. None of them is a colour of the console or an ANSI colour. Some map settings exist, for example `mapStyle` and `mapInfoColor`.
3. We listed all Lua functions with the words ansi, colour, palette, or theme in their names. No function sets the ANSI palette. The table `color_table` is readable. For example `color_table.ansi_001` holds `128,0,0`. Writing to it would not recolour the screen.
4. These functions exist but we did not test them: `setRoomBorderColor`, `setCustomEnvColor`, `setBorderColor`, `setAppStyleSheet`, and `setProfileStyleSheet`.

### 6. Map colours and command line colours

1. The profile had a map with 43 rooms. We created a `Geyser.Mapper` widget and called `setMapBackgroundColor(20, 40, 90)` and `setMapRoomExitsColor(255, 200, 0)`. The map background turned dark blue, and the lines between the rooms turned gold. The player saw both in screenshots.
2. `getMapBackgroundColor()` and `getMapRoomExitsColor()` return the current values. Before the test they returned `0 0 0 255` and `192 192 192`. We put back exactly these values after the test.
3. These map colours belong to the profile. They are not a property of one widget. Any other map widget in the profile changes too.
4. `setCommandBackgroundColor("main", r, g, b)` did not change the command line in a screenshot that we took right after the call.
5. `setCmdLineStyleSheet("main", "QPlainTextEdit{background-color: rgb(20,60,20); color: rgb(255,220,0);}")` turned the command line dark green. We did not type text, so we did not see the text colour.
6. There is no function that reads the colours or the stylesheet of the command line. After a test we cannot restore the exact values of the player. We reset the stylesheet to an empty string, and we set the colours to black and to our best guess of the Mudlet default grey (160, 164). The player can check Preferences.

### 7. Package files and uninstall

We built a small test package with Muddler. It held a script and an image in `src/resources/`.

1. After the install, the image was at `<profile folder>/<package name>/theme.png`. The folder also held `config.lua` and the XML file.
2. `getPackages()` listed the package, and `getPackageInfo("<package>", "version")` returned its version.
3. After `uninstallPackage`, the whole package folder was gone, including the image.
4. A global variable that the package script had set was still set after the uninstall.

## What this means for the design

1. A theme is one Lua table with colours, font sizes, and image paths. One function applies a theme to every element. The function always calls `setStyleSheet` and `setBackgroundImage` again, also when the path is the same. The player can type a command to apply the theme again after an edit of an image.
2. A background that needs text uses a `border-image` stylesheet. A picture without text, such as a logo, uses `setBackgroundImage`.
3. The theme function restyles an `Adjustable.Container` through its inner labels. It uses `pcall`, and a test that creates a container and fails when a field is missing. This test tells us when a new Mudlet version breaks the fields.
4. The player puts images in a folder of the profile, outside the package folder. An uninstall or a reinstall of the package deletes the package folder.
5. Themes can be separate packages. We expect that this works like this, but we did not test it: the theme package holds a `theme.lua` file and its images in its own folder. The GUI scans `getPackages()` for names that start with `rmgui-theme-`. It reads the `theme.lua` file from `<profile folder>/<package name>/`. It scans again when it gets the event `sysInstallPackage`. The simpler choice for the first version is to ship the colour schemes inside the main package.
6. The main text window stays the choice of the player. We cannot recolour it. Each colour scheme can come with a short note that tells the player which Preferences settings match it.
7. The uninstall code must clear the `rmgui` global. A global stays after an uninstall.
8. Map colours work, and they apply to the whole profile. The GUI must read `getMapBackgroundColor()` and `getMapRoomExitsColor()` when it starts, keep the values, and put them back on uninstall.
9. The command line can change with `setCmdLineStyleSheet`. We cannot read the old stylesheet, so the GUI must not change the command line unless the player turns this on. The setting must say that an uninstall resets the command line to the Mudlet default.

## Limits of this research

1. We used one profile, one Mudlet version (5.1.1), and one operating system.
2. The player checked each visual result in a screenshot. The test images are plain colours that we made up.
3. We did not test `changeMenuStyle` visually, the colour of the command line text, `setAppStyleSheet`, `Geyser.StyleSheet`, or saving and loading the layout of a container.
4. We did not test a theme package that the GUI scans for.

## Clean up

We hid the test labels, the container, and the map widget. We set the main window background back to black (0, 0, 0), restored the map colours to their exact old values, reset the command line, and uninstalled the test package. The old command line colours were unknown, so the restore uses black and grey (160, 164) as a guess. The temporary files are in the scratch folder of the session and are not part of the repository.
