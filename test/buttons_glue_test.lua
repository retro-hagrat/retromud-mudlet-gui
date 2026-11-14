-- Tests for src/scripts/buttons/glue.lua. Run from the repo root: lua test/buttons_glue_test.lua
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

local said, elements, slot
local function world(opts)
    opts = opts or {}
    F.reset()
    rmgui, rmap = nil, nil
    said, elements = {}, {}
    dofile(root .. "/src/scripts/core/lifecycle.lua")
    dofile(root .. "/src/scripts/core/env.lua")
    rmgui.theme = {
        register = function(n, fn) elements[n] = fn return true end,
        unregister = function(n) elements[n] = nil return true end,
    }
    slot = Geyser.Container:new({ name = "slot" })
    rmgui.layout = { get = function(s) if s == "buttons" and not opts.noSlot then return slot end end }
    dofile(root .. "/src/scripts/buttons/glue.lua")
    F.expanded = nil
    local env = rmgui.core.makeEnv()
    env.say = function(m, l) said[#said + 1] = m end
    if not opts.noMapper then F.packages.retromud = "1.0" end
    return env
end
local function theme(name)
    elements[name]({ css = function(r) return "css-" .. r end, textColor = function(r) return "col-" .. r end })
end
local function L(n) return F.objects["rmgui.buttons." .. n] end
local function expanded() return table.concat(F.expanded or {}, "|") end
local function pristine(label)
    local c = F.counts()
    eq(c.objects + c.handlers + c.timers + c.triggers, 1, label .. " (only the test slot left)")
end

-- built, themed
local env = world()
rmgui.buttons.init(env)
eq(#F.objects["slot"].children, 4, "four buttons")
for _, n in ipairs({ "where", "scan", "undo", "mapToggle" }) do eq(L(n) ~= nil, true, "label " .. n) end
eq(L("mapToggle").text, "start map", "toggle starts off")
theme("buttons.labels")
eq(L("where").styleSheet, "css-button", "stylesheet")
eq(L("where").textColor, "col-button", "text colour")
eq(L("scan").text, "scan", "text kept")

-- api present
local calls = {}
local function rec(n, ...) local r = table.pack(...) return function() calls[#calls + 1] = n return table.unpack(r, 1, r.n) end end
rmap = { api = { where = rec("where"), scan = rec("scan", nil, "nothing to scan"), undo = function() error("boom") end,
    start = rec("start"), stop = rec("stop"), isMapping = function() return rmap.mapping end } }
L("where"):fireClick()
L("scan"):fireClick()
eq(said[#said], "nothing to scan", "reason said")
L("undo"):fireClick()
eq(said[#said]:find("mapper call failed", 1, true) ~= nil, true, "error said")
eq(table.concat(calls, ","), "where,scan", "api calls")
calls = {}
L("mapToggle"):fireClick(); rmap.mapping = true; L("mapToggle"):fireClick()
eq(table.concat(calls, ","), "start,stop", "toggle via isMapping")
eq(expanded(), "", "no alias with api")
eq(L("mapToggle").text, "stop map", "api that never raises an event: label read back from isMapping (fake reports mapping = true)")
F.fire("rmap.onMapping", true)
eq(L("mapToggle").text, "stop map", "event on")
eq(L("mapToggle").textColor, "col-button", "event redraw colour")
F.fire("rmap.onMapping", false)
eq(L("mapToggle").text, "start map", "event off")

-- api missing (rmap absent, and rmap without api)
rmap = nil
L("where"):fireClick(); L("scan"):fireClick(); L("undo"):fireClick()
L("mapToggle"):fireClick(); L("mapToggle"):fireClick()
eq(expanded(), "rmap where|rmap scan|rmap undo|rmap start|rmap stop", "alias fallback, remembered toggle")
eq(L("mapToggle").text, "start map", "label back to off after the second click without api")
L("mapToggle"):fireClick()
eq(L("mapToggle").text, "stop map", "label follows the click without api (no event needed)")
L("mapToggle"):fireClick()
rmap = {}
F.expanded = {}
L("where"):fireClick()
eq(expanded(), "rmap where", "rmap without api")
-- api without isMapping or start: falls back to alias; failing isMapping falls back to memory
rmap = { api = { isMapping = function() error("x") end, start = rec("start") } }
calls = {}
L("mapToggle"):fireClick()
eq(table.concat(calls, ","), "start", "isMapping failing")

-- init reads isMapping
rmgui.buttons.teardown()
rmap = { api = { isMapping = function() return true end } }
rmgui.buttons.init(env)
eq(L("mapToggle").text, "stop map", "initial state from api")
rmgui.buttons.teardown()
rmap = { api = { isMapping = function() error("x") end } }
rmgui.buttons.init(env)
eq(L("mapToggle").text, "start map", "isMapping fails at init")
rmgui.buttons.teardown()

-- teardown
pristine("teardown")
eq(elements["buttons.labels"], nil, "theme unregistered")
rmgui.buttons.teardown()
pristine("teardown twice")
rmap = nil
rmgui.buttons.init(env)
eq(#F.objects["slot"].children, 4, "init after teardown, no duplicates")
rmgui.buttons.init(env)
eq(#F.objects["slot"].children, 4, "init twice")
rmgui.buttons.teardown()

-- mapper missing
env = world({ noMapper = true })
rmap = { api = { where = rec("where") } }
calls = {}
rmgui.buttons.init(env)
theme("buttons.labels")
eq(L("where").textColor, "col-tab", "muted when mapper missing")
eq(L("where").styleSheet, "css-button", "same stylesheet")
L("where"):fireClick()
eq(said[#said], "the mapper package is not installed", "missing says so")
eq(#calls + #(F.expanded or {}), 0, "nothing called")
rmgui.buttons.teardown()

-- missing slot: build on onLayout; no raise
env = world({ noSlot = true })
rmgui.buttons.init(env)
eq(F.counts().objects, 1, "nothing built without slot")
rmgui.layout.get = function() return slot end
F.fire("rmgui.onLayout", { layout = "wide" })
eq(#slot.children, 4, "built on layout event")
F.fire("rmgui.onLayout", { layout = "wide" })
eq(#slot.children, 4, "second layout event does not duplicate")
rmgui.buttons.teardown()
pristine("teardown after late build")

-- layout.get raising, Geyser failing, registerEvent failing, no theme
env = world()
rmgui.layout.get = function() error("no layout") end
rmgui.buttons.init(env)
eq(F.counts().objects, 1, "layout raising")
rmgui.buttons.teardown()
env = world()
F.failOn = { ["Label:new"] = true }
rmgui.buttons.init(env)
eq(F.counts().objects, 1, "Label:new failing")
rmgui.buttons.teardown()
F.failOn = { ["Label:echo"] = true }
rmgui.buttons.init(env); theme("buttons.labels")
F.failOn = nil
rmgui.buttons.teardown()
env.registerEvent = function() error("no") end
rmgui.buttons.init(env)
eq(F.counts().handlers, 0, "registerEvent failing")
rmgui.buttons.teardown()
env.say = nil
rmgui.buttons.init(env)
L("where"):fireClick()
rmgui.buttons.teardown()

-- core registration and toggle without theme drawn
eq(rmgui.core.state ~= nil, true, "core present")

-- re-running the script file while live must not leak the old instance
env = world(); rmgui.buttons.init(env)
local before = F.counts()
dofile(root .. "/src/scripts/buttons/glue.lua")
local after = F.counts()
eq(after.objects, before.objects, "reload: no duplicate objects")
eq(after.handlers, before.handlers, "reload: no duplicate handlers")
rmgui.buttons.teardown()
pristine("reload then teardown")
F.restore()
-- a mapper without rmap.api that is already on when the GUI loads: the label and the first click follow rmap.mapping
rmgui.buttons.teardown()
env = world(); rmap = { mapping = true }; F.expanded = {}
rmgui.buttons.init(env)
eq(L("mapToggle").text, "stop map", "mapper already on, no api: label says stop map")
L("mapToggle"):fireClick()
eq(expanded(), "rmap stop", "first click stops a mapper that was already on")

print(("buttons_glue: %d checks, %d failed"):format(count, fails))
if COVER then
    debug.sethook()
    local f = io.open(root .. "/src/scripts/buttons/glue.lua")
    local n = 0
    for line in f:lines() do
        n = n + 1
        local t = line:match("^%s*(.-)%s*$")
        if t ~= "" and not t:match("^%-%-") and t ~= "end" and t ~= "else" and t ~= "end)" and t ~= "}" and t ~= "reset()"
            and not hit["@" .. root .. "/src/scripts/buttons/glue.lua:" .. n] and not hit[root .. "/src/scripts/buttons/glue.lua:" .. n] then
            print("uncovered " .. n .. ": " .. t)
        end
    end
end
os.exit(fails == 0 and 0 or 1)
