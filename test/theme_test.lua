-- Tests for src/scripts/theme. Run from the repo root: lua test/theme_test.lua
-- COVER=1 prints the lines of logic.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
dofile(root .. "/src/scripts/theme/presets.lua")
dofile(root .. "/src/scripts/theme/logic.lua")
local T = rmgui.theme

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function has(s, part, label) eq(type(s) == "string" and s:find(part, 1, true) ~= nil, true, label) end
local function lacks(s, part, label) eq(type(s) == "string" and s:find(part, 1, true) == nil, true, label) end
local function problemsMention(problems, part, label)
    local found = false
    for _, p in ipairs(problems) do if p:find(part, 1, true) then found = true end end
    eq(found, true, label)
end

local NAMES = { "dark", "light", "flame", "ocean", "forest" }

---------------------------------------------------------------- presets
for _, n in ipairs(NAMES) do
    local p = T.presets[n]
    eq(type(p), "table", "preset exists: " .. n)
    eq(p.name, n, "preset name matches key: " .. n)
    eq(type(p.title) == "string" and p.title ~= "", true, "preset has a title: " .. n)
    eq(type(p.description) == "string" and p.description ~= "", true, "preset has a description: " .. n)
end
local count5 = 0
for _ in pairs(T.presets) do count5 = count5 + 1 end
eq(count5, 5, "exactly five presets")

-- every preset has every key of dark (THEME-001), and the same types
local function sameShape(a, b, path, label)
    for k, v in pairs(a) do
        eq(b[k] ~= nil, true, label .. " has " .. path .. k)
        if type(v) == "table" and type(b[k]) == "table" then sameShape(v, b[k], path .. k .. ".", label) end
    end
end
for _, n in ipairs(NAMES) do
    sameShape(T.presets.dark, T.presets[n], "", "preset " .. n)
    sameShape(T.presets[n], T.presets.dark, "", "dark vs " .. n)
end

-- presets are different from each other
for i = 1, #NAMES do
    for j = i + 1, #NAMES do
        local a, b = T.presets[NAMES[i]].colors, T.presets[NAMES[j]].colors
        eq(a.surface[1] ~= b.surface[1] or a.surface[2] ~= b.surface[2] or a.surface[3] ~= b.surface[3],
           true, ("surfaces differ: %s vs %s"):format(NAMES[i], NAMES[j]))
        eq(a.accent[1] ~= b.accent[1] or a.accent[2] ~= b.accent[2] or a.accent[3] ~= b.accent[3],
           true, ("accents differ: %s vs %s"):format(NAMES[i], NAMES[j]))
    end
end

-- no pure primary colours: no token is a pure red, green or blue (255,0,0 style)
local function pure(c) return (c[1] == 0 or c[1] == 255) and (c[2] == 0 or c[2] == 255) and (c[3] == 0 or c[3] == 255) end
for _, n in ipairs(NAMES) do
    for k, c in pairs(T.presets[n].colors) do
        if k ~= "map" then eq(pure(c), false, ("%s.%s is not a pure primary"):format(n, k)) end
    end
end

---------------------------------------------------------------- contrast (THEME-013)
eq(math.abs(T.contrast({ 0, 0, 0 }, { 255, 255, 255 }) - 21) < 0.001, true, "black on white is 21")
eq(math.abs(T.contrast({ 255, 255, 255 }, { 255, 255, 255 }) - 1) < 0.001, true, "same colour is 1")
eq(T.contrast({ 10, 20, 30 }, { 240, 240, 240 }) == T.contrast({ 240, 240, 240 }, { 10, 20, 30 }), true, "contrast is symmetric")
eq(math.abs(T.contrast({ 119, 119, 119 }, { 255, 255, 255 }) - 4.48) < 0.02, true, "known WCAG value for #777 on white")
for _, n in ipairs(NAMES) do
    local theme, problems = T.resolve(n)
    eq(#problems, 0, "preset resolves without problems: " .. n)
    local bad = T.contrastProblems(theme)
    eq(#bad, 0, "preset passes contrast: " .. n .. " " .. table.concat(bad, "; "))
end
-- a theme below a limit is reported
local weak = T.resolve("dark", { colors = { text = { 40, 44, 52 } } })
local bad = T.contrastProblems(weak)
eq(#bad >= 2, true, "weak text fails on both surfaces")
problemsMention(bad, "text on surface", "report names the pair")
local weakAccent = T.resolve("dark", { colors = { accent = { 30, 34, 40 } } })
problemsMention(T.contrastProblems(weakAccent), "accent on surface", "weak accent is reported")
local weakMap = T.resolve("dark", { colors = { map = { exits = { 18, 20, 24 } } } })
problemsMention(T.contrastProblems(weakMap), "map exits", "weak map exits are reported")
local weakGauge = T.resolve("dark", { colors = { hp = { 30, 30, 36 } } })
problemsMention(T.contrastProblems(weakGauge), "hp on surface", "weak gauge colour is reported")
-- an override that keeps a preset valid does not add problems
local fine = T.resolve("light", { colors = { accent = { 20, 40, 160 } } })
eq(#T.contrastProblems(fine), 0, "valid override passes contrast")

---------------------------------------------------------------- merge (THEME-010)
local theme, problems = T.resolve("flame")
eq(#problems, 0, "no override: no problems")
eq(theme.colors.accent[1], 255, "flame accent red channel")
eq(theme.name, "flame", "flame name")
theme, problems = T.resolve("nope")
eq(theme, nil, "unknown theme returns nil"); has(problems, "unknown theme", "unknown theme reason")
theme, problems = T.resolve("dark", { colors = { accent = { 1, 2, 3 } } })
eq(theme.colors.accent[2], 2, "override replaces a colour"); eq(#problems, 0, "valid override: no problems")
eq(theme.colors.surface[1], 24, "other colours stay")
eq(T.presets.dark.colors.accent[1], 129, "the preset table is not changed by an override")
theme, problems = T.resolve("dark", { colors = { accent = { 1, 2, 3, 128 } } })
eq(theme.colors.accent[4], 128, "colour with alpha is accepted")
-- nested table
theme = T.resolve("dark", { colors = { map = { background = { 5, 6, 7 } } } })
eq(theme.colors.map.background[3], 7, "nested override applies"); eq(theme.colors.map.exits[1], 120, "nested sibling stays")
-- unknown keys
theme, problems = T.resolve("dark", { bogus = 1, colors = { nonsense = { 1, 2, 3 } } })
eq(#problems, 2, "two unknown keys"); problemsMention(problems, "bogus: unknown key", "top-level unknown key")
problemsMention(problems, "colors.nonsense: unknown key", "nested unknown key"); eq(theme.bogus, nil, "unknown key is not copied")
-- wrong types
local cases = {
    { { colors = { accent = "red" } }, "colors.accent: not a colour", "string for colour" },
    { { colors = { accent = { 1, 2 } } }, "not a colour", "colour too short" },
    { { colors = { accent = { 1, 2, 3, 4, 5 } } }, "not a colour", "colour too long" },
    { { colors = { accent = { 1, 2, 300 } } }, "not a colour", "channel above 255" },
    { { colors = { accent = { 1, -2, 3 } } }, "not a colour", "channel below 0" },
    { { colors = { accent = { 1, "x", 3 } } }, "not a colour", "channel not a number" },
    { { colors = 5 }, "colors: expected a table", "colors not a table" },
    { { fonts = { size = "big" } }, "fonts.size: expected a number", "font size string" },
    { { fonts = { size = 0 } }, "fonts.size: must be above 0", "font size zero" },
    { { fonts = { size = -3 } }, "fonts.size: must be above 0", "font size negative" },
    { { fonts = { family = 12 } }, "fonts.family: expected a string", "family number" },
    { { images = { panel = 5 } }, "images.panel: expected a file name or false", "image number" },
    { { images = { panel = true } }, "images.panel", "image true" },
    { { images = { sidebar = "x.png" } }, "images.sidebar: unknown key", "unknown image role" },
}
for _, c in ipairs(cases) do
    local t, p = T.resolve("dark", c[1])
    eq(#p, 1, c[3] .. ": one problem")
    problemsMention(p, c[2], c[3] .. ": message")
end
theme = T.resolve("dark", { colors = { accent = "red" }, fonts = { size = 12 } })
eq(theme.colors.accent[1], 129, "bad colour keeps the old value"); eq(theme.fonts.size, 12, "good key still applies")
theme = T.resolve("dark", { images = { panel = "p.png" } })
eq(theme.images.panel, "p.png", "image file name accepted")
theme = T.resolve("dark", { images = { panel = false } }); eq(theme.images.panel, false, "image false accepted")
theme, problems = T.resolve("dark", {}); eq(#problems, 0, "empty override")
theme, problems = T.resolve("dark", nil); eq(#problems, 0, "nil override")
-- THEME-001 gaps in a preset are filled from dark
local saved = T.presets.test
T.presets.test = { name = "test", title = "T", description = "d", colors = { accent = { 9, 9, 9 } } }
theme, problems = T.resolve("test")
eq(theme.colors.accent[1], 9, "partial preset keeps its own value"); eq(theme.colors.surface[1], 24, "partial preset is filled from dark")
eq(theme.fonts.size, 10, "partial preset gets fonts from dark"); eq(#problems, 0, "partial preset has no problems")
T.presets.test = saved

---------------------------------------------------------------- stylesheets
local dark = T.resolve("dark")
for _, role in ipairs(T.roles) do
    local css = T.css(role, dark)
    has(css, "QLabel{", role .. ": wrapped in QLabel"); has(css, "background-color: rgb(", role .. ": has a background")
    has(css, "color: rgb(", role .. ": has a text colour"); has(css, "font-size: 10pt;", role .. ": has a font size")
    lacks(css, "border-image", role .. ": no image, no border-image")
end
local css = T.css("statusbar", dark)
has(css, "background-color: rgb(34,38,46);", "statusbar uses surfaceAlt"); has(css, "color: rgb(226,230,236);", "statusbar uses text")
lacks(css, "border:", "statusbar has no border")
css = T.css("window", dark); has(css, "background-color: rgb(24,27,33);", "window uses surface")
css = T.css("panel", dark); has(css, "border: 1px solid rgb(58,64,76);", "panel has a border")
css = T.css("button", dark)
has(css, "QLabel::hover{border: 1px solid rgb(129,140,248);}", "button has an accent hover")
css = T.css("tab", dark); has(css, "color: rgb(150,158,170);", "tab uses textMuted")
css = T.css("tabActive", dark); has(css, "border: 1px solid rgb(129,140,248);", "active tab has an accent border")
lacks(T.css("panel", dark), "::hover", "panel has no hover rule")
-- images
css = T.css("panel", dark, "/home/u/theme/panel.png")
has(css, 'border-image: url("/home/u/theme/panel.png");', "image uses border-image"); lacks(css, "background-color", "image replaces the background")
has(css, "color: rgb(226,230,236);", "text colour stays with an image")
css = T.css("panel", dark, "C:\\Users\\u\\panel.png"); has(css, 'url("C:/Users/u/panel.png")', "backslashes become slashes")
css = T.css("panel", dark, "/home/u/my theme/panel.png"); has(css, 'url("/home/u/my theme/panel.png")', "spaces in the path are kept")
css = T.css("panel", dark, '/x/"; evil: 1; "/p.png'); lacks(css, "border-image", "path with a quote is ignored"); lacks(css, "evil", "no injected rule")
has(css, "background-color", "unsafe image falls back to colour")
css = T.css("panel", dark, "/x/a\nb.png"); lacks(css, "border-image", "path with a newline is ignored")
css = T.css("panel", dark, "/x/a\rb.png"); lacks(css, "border-image", "path with a carriage return is ignored")
-- fonts
local f = T.resolve("dark", { fonts = { family = "Fira Sans", size = 11 } })
css = T.css("statusbar", f); has(css, 'font-family: "Fira Sans";', "font family is set"); has(css, "font-size: 11pt;", "font size is set")
lacks(T.css("statusbar", dark), "font-family", "empty family adds no font-family")
f = T.resolve("dark", { fonts = { family = 'x"; background: red; "' } })
lacks(T.css("statusbar", f), "font-family", "unsafe family is ignored")
-- alpha
local a = T.resolve("dark", { colors = { surface = { 1, 2, 3, 128 } } })
has(T.css("window", a), "rgba(1,2,3,128)", "alpha colour uses rgba")
a = T.resolve("dark", { colors = { surface = { 1, 2, 3, 255 } } }); has(T.css("window", a), "rgb(1,2,3)", "alpha 255 uses rgb")
-- unknown role
local none, why = T.css("nope", dark); eq(none, nil, "unknown role returns nil"); has(why, "unknown role", "unknown role reason")
-- every preset builds a stylesheet for every role
for _, n in ipairs(NAMES) do
    local th = T.resolve(n)
    for _, role in ipairs(T.roles) do eq(type(T.css(role, th)), "string", ("css %s/%s"):format(n, role)) end
end

---------------------------------------------------------------- image lookup (THEME-009)
local dirs = { player = "/p/retromud-gui-theme", themes = "/pkg/themes" }
local files = {}
local function exists(p) return files[p] == true end
eq(T.findImage("panel", "ocean", dirs, exists), nil, "no file: nil")
files["/pkg/themes/ocean/panel.png"] = true
eq(T.findImage("panel", "ocean", dirs, exists), "/pkg/themes/ocean/panel.png", "theme folder is used")
eq(T.findImage("panel", "dark", dirs, exists), nil, "another theme does not use it")
eq(T.findImage("button", "ocean", dirs, exists), nil, "another role does not use it")
files["/p/retromud-gui-theme/panel.png"] = true
eq(T.findImage("panel", "ocean", dirs, exists), "/p/retromud-gui-theme/panel.png", "player folder wins")
eq(T.findImage("panel", "dark", dirs, exists), "/p/retromud-gui-theme/panel.png", "player image applies to every theme")

---------------------------------------------------------------- speed
local t0 = os.clock()
for i = 1, 2000 do
    local th = T.resolve(NAMES[i % 5 + 1], { colors = { accent = { 1, 2, 3 } } })
    for _, role in ipairs(T.roles) do T.css(role, th) end
    T.contrastProblems(th)
end
eq((os.clock() - t0) / 2000 < 0.005, true, "apply work stays under 5 ms")

if COVER then
    debug.sethook()
    local path = root .. "/src/scripts/theme/logic.lua"
    local n = 0
    for l in io.lines(path) do
        n = n + 1
        local code = l:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$") or code:match("^local function")
            or code:match("^function ") or code:match("^[%]})]+,?$") or code:match("^elseif") or code:match("^}$")
        if not skip and not hit[path .. ":" .. n] and not hit[("%s:%d"):format(path, n)] then
            print(("not run  logic.lua:%d  %s"):format(n, code))
        end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
