-- Tests for src/scripts/layout/glue.lua. Run from the repo root: lua test/layout_glue_test.lua
-- COVER=1 prints the lines of glue.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local F = dofile(root .. "/test/fake_mudlet.lua")
dofile(root .. "/src/scripts/theme/presets.lua")
dofile(root .. "/src/scripts/theme/logic.lua")
dofile(root .. "/src/scripts/theme/apply.lua")
dofile(root .. "/src/scripts/core/lifecycle.lua")
dofile(root .. "/src/scripts/core/settings.lua")
dofile(root .. "/src/scripts/core/env.lua")
dofile(root .. "/src/scripts/layout/calc.lua")
local L, T = rmgui.layout, rmgui.theme

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

dofile(root .. "/src/scripts/layout/glue.lua")

local SAVED = 0
local function mk()
    F.reset()
    F.borders = { top = 5, right = 6, bottom = 7, left = 8 }
    local env = rmgui.core.makeEnv()
    env.settings = rmgui.settings.defaults()
    env.saveSettings = function() SAVED = SAVED + 1 end
    env.raised = {}
    local raise = env.raise
    env.raise = function(e, ...) env.raised[#env.raised + 1] = { e, ... }; return raise(e, ...) end
    env.said = {}
    env.say = function(m) env.said[#env.said + 1] = m end
    return env
end
local function lastLayout(env)
    for i = #env.raised, 1, -1 do if env.raised[i][1] == "rmgui.onLayout" then return env.raised[i][2] end end
end
local function empty(label)
    local c = F.counts()
    eq(c.objects + c.timers + c.handlers + c.triggers, 0, label .. " leaves nothing")
end

---------------------------------------------------------------- wide init
local env = mk()
L.init(env)
local r = lastLayout(env)
eq(r.layout, "wide", "1920 wide is wide")
eq(F.borders.top, 36, "top border")
eq(F.borders.left, r.left, "left border")
eq(F.borders.right, r.right, "right border")
eq(F.borders.bottom, 0, "bottom border stays 0")
eq(F.objects["rmgui.layout.leftBg"] ~= nil and F.objects["rmgui.layout.rightBg"] ~= nil, true, "backgrounds")
for _, n in ipairs({ "top", "chat", "map", "vitals", "buttons" }) do
    eq(F.objects["rmgui.layout." .. n] ~= nil, true, "object " .. n)
    eq(L.get(n) ~= nil, true, "get " .. n)
    eq(L.get(n).name, "rmgui.layout." .. n .. ".inner", "inner name " .. n)
end
eq(L.get("nope"), nil, "unknown slot")
local chat, chatIn = F.objects["rmgui.layout.chat"], L.get("chat")
eq(chat:get_height(), 904 - 36 - 12, "chat fills the Inside area of the column (3 x padding 4 less)")
eq(chatIn:get_x() - chat:get_x(), 16, "inner inset 16")
eq(chatIn:get_width(), r.left - 8 - 32, "inner width: column less 2 x padding less 2 x frame")
local map, vit, btn = F.objects["rmgui.layout.map"], F.objects["rmgui.layout.vitals"], F.objects["rmgui.layout.buttons"]
eq(vit:get_y() - (map:get_y() + map:get_height()), 4, "gap map/vitals")
eq(btn:get_y() - (vit:get_y() + vit:get_height()), 4, "gap vitals/buttons")
eq(btn:get_y() + btn:get_height() <= 904, true, "buttons within window")
local top = L.get("top")
eq(top:get_x() - F.objects["rmgui.layout.top"]:get_x(), 16, "top inset x")
eq(top:get_y() - F.objects["rmgui.layout.top"]:get_y(), 8, "top inset y")
eq(F.objects["rmgui.layout.leftCol"].attached, "left", "left col attached")
eq(F.objects["rmgui.layout.topBar"].attached, "top", "top attached")
eq(F.counts().handlers, 1, "one resize handler")

---------------------------------------------------------------- theme element
T.apply("perdow", env, env.settings)
eq(F.objects["rmgui.layout.chat"].styleSheet ~= nil, true, "panel css")
eq(F.objects["rmgui.layout.top"].styleSheet ~= nil, true, "statusbar css")
eq(F.objects["rmgui.layout.leftBg"].styleSheet ~= nil, true, "bg css")

-- parenting and ABSOLUTE position. Two real bugs hid here: children landed on the root window
-- because the parent was passed in the constructor table (Geyser takes it as the second
-- argument), and children of an Adjustable.Container overflowed because Mudlet positions them in
-- the Inside area but sizes them against the whole container (so they must be parented to Inside).
do
    local function obj(n) return F.objects["rmgui.layout." .. n] end
    local left, right, bar = obj("leftCol"), obj("rightCol"), obj("topBar")
    local rr = lastLayout(env)
    eq(right:get_x(), 1920 - rr.right, "right column starts where its border starts")
    eq(left:get_x(), 0, "left column at the left edge")
    local function inside(child, col, label)
        eq(child:get_x() >= col:get_x() and child:get_y() >= col:get_y(), true, label .. " starts inside the column")
        eq(child:get_x() + child:get_width() <= col:get_x() + col:get_width(), true, label .. " ends inside the column horizontally")
        eq(child:get_y() + child:get_height() <= col:get_y() + col:get_height(), true, label .. " ends inside the column vertically")
    end
    for _, n in ipairs({ "rightBg", "map", "vitals", "buttons" }) do
        eq(obj(n).parent, right.Inside, n .. " is a child of the right column Inside area")
        inside(obj(n), right, n)
        eq(obj(n):get_x(), right.Inside:get_x(), n .. " absolute x is the Inside x")
    end
    for _, n in ipairs({ "leftBg", "chat" }) do
        eq(obj(n).parent, left.Inside, n .. " is a child of the left column Inside area")
        inside(obj(n), left, n)
        eq(obj(n):get_x(), left.Inside:get_x(), n .. " absolute x is the Inside x")
        eq(obj(n):get_y(), left.Inside:get_y(), n .. " absolute y is the Inside y")
    end
    eq(obj("top").parent, bar.Inside, "status bar label is a child of the top bar Inside area")
    inside(obj("top"), bar, "status bar label")
    eq(obj("top"):get_y(), bar:get_y(), "status bar label absolute y is the top bar y (no padding on the bar)")
    for _, n in ipairs({ "chat", "map", "vitals", "buttons" }) do
        eq(obj(n .. ".inner").parent, obj(n), n .. " inner is a child of its panel")
    end
    eq(obj("top.inner").parent, obj("top"), "top inner is a child of the status bar label")
    eq(left.padding, 4, "column padding 4"); eq(bar.padding, 0, "top bar padding 0")
    eq(left.minimizeLabel.hidden and left.exitLabel.hidden and true or false, true, "title buttons hidden")
end
eq(F.objects["rmgui.layout.chat"].text, nil, "echoes nothing")
-- a bigger image scale re-applies the layout and widens the frame
local th = T.resolve("perdow"); th.imageScale = 2
local fn
local oldRegister = T.register
T.register = function(name, f) fn = f; return oldRegister(name, f) end
L.init(env)
T.register = oldRegister
n0 = #env.raised
fn({ theme = th, css = function() return "css" end })
eq(#env.raised > n0, true, "scale change re-applies")
eq(L.get("chat"):get_x() - F.objects["rmgui.layout.chat"]:get_x(), 32, "frame doubles at scale 2")
n0 = #env.raised
fn({ theme = th, css = function() return "css" end })
eq(#env.raised, n0, "same scale no re-apply")

---------------------------------------------------------------- resize debounce
local base = #env.raised
F.setWindowSize(1500, 800)
F.setWindowSize(1400, 800)
eq(F.counts().timers, 1, "one pending timer")
eq(#env.raised, base, "nothing applied before the timer")
F.runTimers(0.1)
eq(#env.raised, base, "still waiting")
F.runTimers(0.2)
eq(#env.raised, base + 1, "applied once")
eq(F.counts().timers, 0, "timer gone")
eq(lastLayout(env).layout, "wide", "1400 still wide")

---------------------------------------------------------------- commands
eq(L.command("compact", env), true, "compact handled")
eq(env.settings.layout.mode, "compact", "mode saved in settings")
eq(SAVED > 0, true, "saveSettings called")
eq(F.borders.left, 0, "compact left 0")
eq(F.borders.right, 0, "compact right 0")
eq(F.borders.top, 36, "status bar stays")
eq(F.objects["rmgui.layout.leftCol"].hidden, true, "left hidden")
eq(F.objects["rmgui.layout.rightCol"].hidden, true, "right hidden")
eq(lastLayout(env).layout, "compact", "compact raised")
eq(L.command(" WIDE ", env), true, "wide handled")
eq(F.objects["rmgui.layout.leftCol"].hidden, false, "shown again")
eq(F.borders.left > 0, true, "wide borders back")
eq(L.command("auto", env), true, "auto handled")
eq(env.settings.layout.mode, "auto", "auto stored")
env.said = {}
eq(L.command("sideways", env), false, "usage returns false")
eq(env.said[1]:find("usage", 1, true) ~= nil, true, "usage text")
eq(L.command(nil, env), false, "nil arg is usage")
eq(L.command("wide", {}), true, "command with empty env")
eq(L.command("wide", nil), true, "command with env from init")
-- narrow window: auto goes compact
L.command("auto", env)
F.setWindowSize(900, 700); F.runTimers(1)
eq(lastLayout(env).layout, "compact", "narrow is compact")

---------------------------------------------------------------- teardown
L.teardown()
eq(F.borders.top, 5, "top restored"); eq(F.borders.right, 6, "right restored")
eq(F.borders.bottom, 7, "bottom restored"); eq(F.borders.left, 8, "left restored")
empty("teardown")
eq(L.get("chat"), nil, "get after teardown")
eq(L.apply(), nil, "apply after teardown")
L.teardown(); empty("second teardown")
local before = #F.calls
L.teardown(); eq(#F.calls, before, "teardown twice does nothing")

---------------------------------------------------------------- init again, double init
env = mk()
L.init(env)
local c1 = F.counts()
L.init(env)
local c2 = F.counts()
eq(c2.objects, c1.objects, "no duplicate objects on second init")
eq(c2.handlers, 1, "no duplicate handler")
eq(F.borders.top, 36, "borders after re-init")
L.teardown()
eq(F.borders.left, 8, "restored to the original after double init")
empty("re-init teardown")

---------------------------------------------------------------- pending timer killed on teardown
env = mk()
L.init(env)
F.setWindowSize(1600, 900)
eq(F.counts().timers, 1, "timer pending")
L.teardown()
empty("teardown with pending timer")

---------------------------------------------------------------- failures must not raise
env = mk()
F.failOn = { ["Label:new"] = true }
eq(pcall(L.init, env), true, "failing Label does not raise")
eq(L.get("chat"), nil, "no slots after failed build")
eq(env.said[1] ~= nil, true, "failure said")
eq(lastLayout(env).failed, true, "onLayout still raised")
eq(L.apply().failed, true, "apply without objects reports failed")
L.teardown()
-- a Label that fails inside the Adjustable constructor leaves an object only that constructor holds
env = mk()
F.failOn = { ["Container:new"] = true }
eq(pcall(L.init, env), true, "failing Container does not raise")
eq(L.get("chat"), nil, "no slots after failed Container")
L.teardown(); empty("teardown after failed build")

-- one failing call in apply: said, event still raised, objects still removed
env = mk()
L.init(env)
F.failOn = { ["Label:move"] = true }
local n1 = #env.raised
L.apply()
F.failOn = nil
eq(#env.raised, n1 + 1, "event raised after failed apply")
L.teardown(); empty("teardown after failed apply")

-- a failing Adjustable and failing hide/delete in teardown
env = mk()
F.failOn = { ["Adjustable:new"] = true }
eq(pcall(L.init, env), true, "failing Adjustable does not raise")
L.teardown(); empty("teardown after failed Adjustable")
env = mk()
L.init(env)
F.failOn = { ["Label:hide"] = true }
eq(pcall(L.teardown), true, "failing hide in teardown")
F.failOn = nil
L.teardown()
eq(F.borders.left, 8, "borders restored despite failing hide")

-- missing settings, bad window size, failing registerEvent, no theme module state
env = mk()
env.settings = {}
env.windowSize = function() return nil end
env.registerEvent = function() error("no events") end
eq(pcall(L.init, env), true, "bare env does not raise")
eq(lastLayout(env).layout, "compact", "bad size is compact")
L.command("wide", env)
L.teardown(); empty("bare env teardown")
env = mk()
env.say = nil
env.raise = nil
env.settings.layout = nil
eq(pcall(L.init, env), true, "env without say and raise")
eq(L.command("bogus", env), false, "usage without say")
eq(L.command("auto", env), true, "command without settings.layout")
L.teardown(); empty("no-say teardown")
-- the theme element after teardown is a no-op and unregistered
env = mk()
L.init(env)
L.teardown()
eq(T.unregister("layout.bars"), false, "theme element removed")

---------------------------------------------------------------- adversarial regressions
-- the file run again while the old state exists (player saves it in the editor)
env = mk()
L.init(env)
dofile(root .. "/src/scripts/layout/glue.lua")
L.init(env)
eq(F.counts().objects, 27, "re-run file then init: no duplicates (24 labels and containers plus 3 Inside areas)")
L.teardown(); empty("re-run file teardown")
eq(F.borders.left, 8, "re-run file restores borders")
-- a timer that raises must not raise into the resize event
env = mk()
L.init(env)
env.timer = function() error("boom") end
eq(pcall(F.setWindowSize, 1000, 700), true, "failing timer in resize")
L.teardown(); empty("failing timer teardown")
-- settings.layout that is not a table
env = mk()
env.settings.layout = true
L.init(env)
eq(lastLayout(env).failed, nil, "non-table layout setting is not a failure")
eq(F.borders.top, 36, "status bar border with bad settings")
L.teardown()
-- a failed apply must not leave the stub column sizes in the borders
env = mk()
env.windowSize = function() return "a", "b" end
L.init(env)
eq(F.borders.left, 0, "failed apply clears borders")
L.teardown()

-- registered with core
rmgui.core.start(mk())
eq(F.objects["rmgui.layout.chat"] ~= nil, true, "core.start inits layout")
rmgui.core.stop()
empty("core.stop")

if COVER then
    debug.sethook()
    local f = io.open(root .. "/src/scripts/layout/glue.lua")
    local i = 0
    for line in f:lines() do
        i = i + 1
        if line:match("%S") and not line:match("^%s*%-%-") and not line:match("^%s*end[%s,)]*$")
            and not line:match("^%s*else%s*$") and not line:match("^%s*[})]+,?%s*$")
            and not hit["@" .. root .. "/src/scripts/layout/glue.lua:" .. i]
            and not hit[root .. "/src/scripts/layout/glue.lua:" .. i] then
            print("not run: " .. i .. ": " .. line)
        end
    end
    f:close()
end
F.restore()
print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
