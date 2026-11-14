-- Tests for src/scripts/themepicker/glue.lua. Run from the repo root: lua test/themepicker_glue_test.lua
-- COVER=1 prints the lines of glue.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l") end
local F = dofile(root .. "/test/fake_mudlet.lua")

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function has(s, part, label) eq(type(s) == "string" and s:find(part, 1, true) ~= nil, true, label) end

local said, saves, slot, env
local NAMES = { "crypt", "perdow", "raji", "sosel", "welstar", "wysoom" }

local function world(opts)
    opts = opts or {}
    F.reset()
    rmgui = nil
    said, saves = {}, 0
    dofile(root .. "/src/scripts/core/lifecycle.lua")
    dofile(root .. "/src/scripts/core/env.lua")
    dofile(root .. "/src/scripts/theme/presets.lua")
    dofile(root .. "/src/scripts/theme/logic.lua")
    dofile(root .. "/src/scripts/theme/apply.lua")
    slot = Geyser.Container:new({ name = "slot", x = 1776, y = 0, width = 144, height = 20 })
    rmgui.layout = { get = function(s) if s == "picker" and not opts.noSlot then return slot end end }
    dofile(root .. "/src/scripts/themepicker/glue.lua")
    env = rmgui.core.makeEnv()
    env.say = function(m) said[#said + 1] = m end
    env.settings = { theme = "perdow", mapTheming = true, cmdlineTheming = false }
    if not opts.noUi then env.settings.ui = { hintShown = opts.hintShown or false } end
    env.saveSettings = function() saves = saves + 1 end
    return env
end
local function obj(n) return F.objects["rmgui.picker." .. n] end

local function nameOnButton() return obj("button").text end
local function arrowCell() return obj("arrow") and obj("arrow").text end

local function row(n) return obj("row." .. n) end
local function counts() local c = F.counts() return c.objects end
local function applyTheme(name) rmgui.theme.apply(name, env, env.settings) end
local function hintCount()
    local n = 0
    for _, m in ipairs(said) do if m:find("tip: click the theme button", 1, true) then n = n + 1 end end
    return n
end
local function pristine(label)
    local c = F.counts()
    eq(c.objects, 1, label .. " objects (only the slot)")
    eq(c.handlers, 0, label .. " handlers")
    eq(c.timers + c.triggers, 0, label .. " timers and triggers")
end

---------------------------------------------------------------- build with slot, styled
world()
rmgui.themepicker.init(env)
eq(obj("button") ~= nil, true, "button built")
eq(obj("button").parent, slot, "button parent is the slot")
eq(obj("button").tooltip, "Change the look", "tooltip")
eq(nameOnButton(), "Perdow", "name before any theme apply")
eq(arrowCell() ~= nil and arrowCell():find("v", 1, true) ~= nil, true, "the arrow is in its own cell at the right, not after the name")
eq(obj("button").text:find("v", 1, true), nil, "no arrow glued to the name")
eq(obj("arrow").parent, obj("button"), "the arrow label is a child of the button")
eq(obj("arrow"):get_x() + obj("arrow"):get_width(), slot:get_x() + slot:get_width(), "the arrow label ends at the right edge")
eq(hintCount(), 1, "hint said")
eq(env.settings.ui.hintShown, true, "hint remembered")
eq(saves, 1, "hint saved")
applyTheme("crypt")
eq(nameOnButton(), "Crypt", "name follows theme")
local th = rmgui.theme.resolve("crypt")
has(obj("button").styleSheet, "background-color: rgb(32,27,36)", "button bg is surfaceAlt")
has(obj("button").styleSheet, "border: 1px solid rgb(214,64,92)", "button border is accent")
has(obj("button").styleSheet, "font-size: 10pt", "button font")
eq(obj("button").textColor, rmgui.theme.textColor("button", th), "button text colour")
eq(obj("button").styleSheet:find("border-image", 1, true), nil, "no nine-slice on the button")
applyTheme("welstar")
eq(nameOnButton(), "Welstar", "name per theme")

---------------------------------------------------------------- open: counts and geometry
local before = counts()
obj("button"):fireClick()
eq(counts() - before, 8, "backdrop + panel + 6 rows")
eq(obj("backdrop") ~= nil and obj("panel") ~= nil, true, "backdrop and panel exist")
local bd, pn = obj("backdrop"), obj("panel")
eq(bd:get_x() + bd:get_y(), 0, "backdrop at origin")
eq(bd:get_width(), 1920, "backdrop width")
eq(bd:get_height(), 904, "backdrop height")
has(bd.styleSheet, "background-color: rgba(0,0,0,0)", "backdrop transparent")
eq(pn:get_width(), 220, "panel width")
eq(pn:get_x() + pn:get_width(), 1920, "panel right aligned")
eq(pn:get_y(), 20, "panel below the bar")
eq(pn:get_y() + pn:get_height() <= 904, true, "panel inside")
has(pn.styleSheet, "background-color: rgb(247,246,241)", "panel surface")
has(pn.styleSheet, "border: 1px solid rgb(40,72,168)", "panel accent border")
for i, n in ipairs(NAMES) do
    local r = row(n)
    eq(r ~= nil, true, "row " .. n)
    eq(r:get_height(), 40, "row height " .. n)
    eq(r:get_y() - pn:get_y(), 4 + (i - 1) * 44, "row y " .. n)
    eq(r.parent, pn, "row parent " .. n)
end
-- own theme per row
for _, n in ipairs(NAMES) do
    local t = rmgui.theme.resolve(n)
    local c = t.colors.surfaceAlt
    has(row(n).styleSheet, ("rgb(%d,%d,%d)"):format(c[1], c[2], c[3]), "row colour " .. n)
    eq(row(n).textColor, rmgui.theme.textColor("button", t), "row echo colour " .. n)
    eq(row(n).text:find(rmgui.theme.presets[n].title, 1, true) == 1, true, "row title " .. n)
end
eq(row("welstar").text, "Welstar  (current)", "current marker")
eq(row("crypt").text, "Crypt", "no marker elsewhere")
-- button click again closes
obj("button"):fireClick()
eq(counts(), before, "closed by the button")
eq(obj("panel"), nil, "panel gone")

---------------------------------------------------------------- image path in a row
env.files = nil
F.files[env.dirs.themes .. "/raji/button.png"] = "x"
obj("button"):fireClick()
has(row("raji").styleSheet, "raji/button.png", "row uses its own image")
eq(row("crypt").styleSheet:find("border-image", 1, true), nil, "other rows without image")
obj("backdrop"):fireClick()
eq(obj("panel"), nil, "backdrop click closes")
eq(counts(), before, "backdrop close leaves nothing")

---------------------------------------------------------------- row click
local s0 = saves
obj("button"):fireClick()
row("sosel"):fireClick()
eq(rmgui.theme.active(), "sosel", "theme applied")
eq(env.settings.theme, "sosel", "setting changed")
eq(saves, s0 + 1, "saved once")
eq(obj("panel"), nil, "panel closed after pick")
eq(counts(), before, "no leftovers after pick")
eq(nameOnButton(), "Sosel", "button follows the pick")
obj("button"):fireClick()
eq(row("sosel").text, "Sosel  (current)", "marker moved")
row("sosel"):fireClick()
eq(saves, s0 + 1, "current theme row: no save")
eq(obj("panel"), nil, "current theme row closes")
-- failing command: panel closed, no raise
local realCmd = rmgui.theme.command
rmgui.theme.command = function() return false, false end
obj("button"):fireClick(); row("crypt"):fireClick()
eq(saves, s0 + 1, "failed command no save")
eq(obj("panel"), nil, "failed command closes")
rmgui.theme.command = function() error("boom") end
obj("button"):fireClick(); row("crypt"):fireClick()
eq(obj("panel"), nil, "raising command closes")
has(said[#said], "boom", "raising command said")
rmgui.theme.command = realCmd
-- save raising
env.saveSettings = function() error("disk") end
obj("button"):fireClick(); row("crypt"):fireClick()
has(said[#said], "disk", "save error said")
env.saveSettings = function() saves = saves + 1 end

---------------------------------------------------------------- close events
obj("button"):fireClick()
F.fire("rmgui.onLayout", { layout = "wide" })
eq(obj("panel"), nil, "layout event closes")
eq(obj("button") ~= nil, true, "button kept on same slot")
obj("button"):fireClick()
F.setWindowSize(1000, 600)
eq(obj("panel"), nil, "resize closes")
eq(counts(), before, "resize leaves nothing")
-- theme change from elsewhere closes and restyles
obj("button"):fireClick()
applyTheme("raji")
eq(obj("panel"), nil, "theme change closes")
eq(nameOnButton(), "Raji", "theme change redraws")

---------------------------------------------------------------- clamping
F.setWindowSize(1920, 904)
slot.x = "10px"
obj("button"):fireClick()
eq(obj("panel"):get_x(), 0, "button near the left edge clamps to 0")
obj("button"):fireClick()
slot.x = "1776px"
F.setWindowSize(150, 120)
obj("button"):fireClick()
eq(obj("panel"):get_width(), 150, "panel narrower in a small window")
eq(obj("panel"):get_x(), 0, "small window x")
eq(obj("panel"):get_y(), 0, "small window y clamped")
obj("button"):fireClick()
F.setWindowSize(1920, 904)

---------------------------------------------------------------- late build on rmgui.onLayout
world({ noSlot = true })
rmgui.themepicker.init(env)
eq(obj("button"), nil, "no slot, no button")
eq(hintCount(), 0, "no hint without a button")
eq(env.settings.ui.hintShown, false, "hint kept for later")
local lateSlot = Geyser.Container:new({ name = "late", x = 1776, y = 0, width = 144, height = 20 })
rmgui.layout.get = function() return lateSlot end
applyTheme("sosel")
F.fire("rmgui.onLayout", { layout = "wide" })
eq(obj("button") ~= nil, true, "built on layout event")
eq(nameOnButton(), "Sosel", "late button themed")
eq(hintCount(), 1, "hint after the late build")
F.fire("rmgui.onLayout", { layout = "wide" })
eq(#lateSlot.children, 1, "no second button")
eq(hintCount(), 1, "hint once")
-- slot replaced: rebuilt
local other = Geyser.Container:new({ name = "other", x = 1776, y = 0, width = 144, height = 20 })
rmgui.layout.get = function() return other end
F.fire("rmgui.onLayout", { layout = "compact" })
eq(#lateSlot.children, 0, "old button gone")
eq(#other.children, 1, "button rebuilt in the new slot")
-- layout missing entirely
rmgui.layout = nil
F.fire("rmgui.onLayout", {})
eq(obj("button") ~= nil, true, "no layout: old button stays, no raise")

---------------------------------------------------------------- hint rules
world({ hintShown = true })
rmgui.themepicker.init(env)
eq(hintCount(), 0, "no hint when already shown")
eq(saves, 0, "no save when already shown")
world({ noUi = true })
rmgui.themepicker.init(env)
eq(hintCount(), 1, "hint with a missing ui table")
eq(env.settings.ui.hintShown, true, "ui table created")
rmgui.themepicker.init(env)
eq(hintCount(), 1, "no second hint after re-init")
world()
env.settings = nil
rmgui.themepicker.init(env)
eq(obj("button") ~= nil, true, "missing settings: still builds")
eq(hintCount(), 0, "missing settings: no hint")
world()
env.saveSettings = function() error("x") end
rmgui.themepicker.init(env)
eq(hintCount(), 1, "save failure does not stop the hint")

---------------------------------------------------------------- double init, teardown
world()
rmgui.themepicker.init(env)
rmgui.themepicker.init(env)
eq(#slot.children, 1, "double init: one button")
eq(#F.handlers, 2, "double init: two handlers")
obj("button"):fireClick()
rmgui.themepicker.teardown()
pristine("teardown with panel open")
rmgui.themepicker.teardown()
pristine("second teardown")
eq(rmgui.theme.unregister("picker.button"), false, "element unregistered")
rmgui.themepicker.init(env)
eq(#slot.children, 1, "init after teardown")
eq(#F.handlers, 2, "init after teardown handlers")
rmgui.themepicker.teardown()
world()
rmgui.themepicker.teardown()
eq(counts(), 1, "teardown before init")
rmgui.core.init = nil

---------------------------------------------------------------- re-run of the file
world()
rmgui.themepicker.init(env)
applyTheme("crypt")
dofile(root .. "/src/scripts/themepicker/glue.lua")
eq(#slot.children, 1, "re-run: one button")
eq(#F.handlers, 2, "re-run: handlers not doubled")
eq(obj("button") ~= nil, true, "re-run: button back")
eq(rmgui.themepicker.state.env, env, "re-run: same env")
rmgui.themepicker.teardown()
pristine("re-run teardown")

---------------------------------------------------------------- failing Geyser calls
local function failing(key, label)
    world()
    F.failOn = { [key] = true }
    local ok, err = pcall(rmgui.themepicker.init, env)
    eq(ok, true, label .. " init no raise " .. tostring(err))
    local ok2 = pcall(function() if obj("button") then obj("button"):fireClick() end end)
    eq(ok2, true, label .. " click no raise")
    F.fire("rmgui.onLayout", {})
    F.failOn = nil
    rmgui.themepicker.teardown()
    pristine(label)
end
failing("Label:new", "Label:new")
failing("Label:echo", "echo")
failing("Label:setStyleSheet", "setStyleSheet")
failing("Label:setClickCallback", "setClickCallback")
-- button builds, panel fails
world()
rmgui.themepicker.init(env)
applyTheme("crypt")
F.failOn = { ["Label:setStyleSheet"] = true }
obj("button"):fireClick()
eq(obj("panel"), nil, "failed panel is closed")
eq(counts(), 3, "failed panel leaves nothing")
has(said[#said], "panel:", "failed panel said")
local n = #said
obj("button"):fireClick()
eq(#said, n, "same failure said once")
F.failOn = nil
-- row fails midway
F.failOn = { ["Label:echo"] = true }
obj("button"):fireClick()
eq(counts(), 3, "failed row leaves nothing")
F.failOn = nil
-- env failing
world()
env.registerEvent = function() error("no") end
eq(pcall(rmgui.themepicker.init, env), true, "registerEvent raising")
rmgui.themepicker.teardown()
world()
rmgui.themepicker.init(env)
env.killEvent = function() error("no") end
eq(pcall(rmgui.themepicker.teardown), true, "killEvent raising")
world()
rmgui.themepicker.init(env)
env.windowSize = function() error("no") end
obj("button"):fireClick()
eq(obj("panel"), nil, "windowSize raising")
-- a raising event handler
world()
rmgui.themepicker.init(env)
rmgui.layout = { get = function() error("layout") end }
eq(pcall(F.fire, "rmgui.onLayout", {}), true, "layout raising in handler")
-- init must never raise, even with a bad env
world()
eq(pcall(rmgui.themepicker.init, nil), true, "init(nil) does not raise")
eq(pcall(rmgui.themepicker.init, "x"), true, "init(string) does not raise")
eq(pcall(rmgui.themepicker.teardown), true, "teardown after bad init")
pristine("bad env")

if COVER then
    debug.sethook()
    local f = io.open(root .. "/src/scripts/themepicker/glue.lua")
    local i = 0
    for line in f:lines() do
        i = i + 1
        local src = "@" .. root .. "/src/scripts/themepicker/glue.lua"
        if not hit[src:sub(2) .. ":" .. i] and line:match("%S") and not line:match("^%s*%-%-") and not line:match("^%s*end[%s,%)]*$") and not line:match("^%s*else%s*$") then
            print(("uncovered %d: %s"):format(i, line))
        end
    end
end
print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
