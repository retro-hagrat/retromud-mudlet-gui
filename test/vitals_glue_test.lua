-- Tests for src/scripts/vitals/glue.lua against the fake Mudlet. Run from the repo root: lua test/vitals_glue_test.lua
-- COVER=1 prints the lines of glue.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local F = dofile(root .. "/test/fake_mudlet.lua")
F.reset()
for _, f in ipairs({ "core/lifecycle", "core/env", "theme/presets", "theme/logic", "theme/apply", "vitals/parser", "vitals/glue" }) do
    dofile(root .. "/src/scripts/" .. f .. ".lua")
end
local V = rmgui.vitals

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

local PROMPT = "Hp: 296/296 Sp: 120/150 Ep: 80/90 >"
local env = rmgui.core.makeEnv()
local slot
local function layoutGet(name) if name == "vitals" then return slot end end
local raised = {}
local function setup(withSlot)
    F.reset()
    rmgui.theme.state.active = nil
    slot = withSlot and Geyser.Container:new({ name = "test.slot", x = 0, y = 0, width = 200, height = 100 }) or nil
    rmgui.layout = { get = layoutGet }
    raised = {}
    env.registerEvent("rmgui.onVitals", function(_, t) raised[#raised + 1] = t end)
    V.init(env)
end
local function gauge(k) return F.objects["rmgui.vitals." .. k] end
local function label(k) return F.objects["rmgui.vitals." .. k .. "label"] end -- the numbers live beside the bar, not on it
local function mod() -- only this module's things
    local n = 0
    for _, o in ipairs(F.objectList) do if o.name:find("rmgui.vitals.", 1, true) == 1 then n = n + 1 end end
    return n
end
local function setValueCalls(g) return g.setCount or 0 end
local function counted(g)
    local orig = g.setValue
    g.setCount = 0
    g.setValue = function(...) g.setCount = g.setCount + 1 return orig(...) end
end

-- registered
eq(rmgui.core.state().order[#rmgui.core.state().order], "vitals", "registered with the lifecycle")

-- build and prompt
setup(true)
eq(gauge("hp") and gauge("sp") and gauge("ep") and true, true, "three gauges")
eq(gauge("hp").parent, slot, "gauges live in the vitals slot")
eq(label("hp").parent, slot, "number labels live in the vitals slot")
for _, k in ipairs({ "hp", "sp", "ep" }) do
    local g, l = gauge(k), label(k)
    eq(l:get_x() + l:get_width() <= g:get_x(), true, k .. " number label ends before its bar starts (no text on the bar)")
    eq(g:get_x() + g:get_width() <= slot:get_x() + slot:get_width() + 0.5, true, k .. " bar stays in the slot")
    eq(l:get_y(), g:get_y(), k .. " label and bar share a row")
end
eq(#F.triggers, 1, "one trigger")
eq(label("hp").text, "HP --", "before the first prompt the label is not blank")
rmgui.theme.apply("welstar", env, {})
eq(label("hp").text, "HP --", "placeholder survives a theme change")
eq(label("hp").textColor, rmgui.theme.textColor("panel", rmgui.theme.resolve("welstar")), "placeholder is in the theme text colour")
F.feedLine(PROMPT)
eq(label("hp").text, "HP", "label carries only the name")
eq(gauge("hp").text.text, "296/296", "numbers are on the bar")
eq(gauge("sp").text.text, "120/150", "sp text")
eq(gauge("ep").value, 80, "ep value")
eq(gauge("sp").max, 150, "sp max")
eq(#raised, 1, "onVitals raised")
eq(raised[1], V.last, "raised the table as is")

-- unchanged prompt does not touch gauges
for _, k in ipairs({ "hp", "sp", "ep" }) do counted(gauge(k)) end
F.feedLine(PROMPT)
F.feedLine(PROMPT)
eq(setValueCalls(gauge("hp")), 0, "unchanged prompt: no setValue")
eq(#raised, 1, "unchanged prompt: no event")
F.feedLine("Hp: 290/296 Sp: 120/150 Ep: 80/90 >")
eq(setValueCalls(gauge("hp")), 1, "changed prompt: one setValue")
eq(setValueCalls(gauge("ep")), 1, "changed prompt redraws all")
eq(#raised, 2, "changed prompt: event")

-- negative current: bar clamped, text real
F.feedLine("Hp: -12/296 Sp: 120/150 Ep: 80/90 >")
eq(gauge("hp").value, 0, "negative clamped for the bar")
eq(gauge("hp").text.text, "-12/296", "negative shown in text")
eq(gauge("hp").text.textColor, "black", "numbers are black")
eq(gauge("hp").text.textFormat, "c", "numbers are centred")

F.feedLine("Hp: 400/296 Sp: 120/150 Ep: 80/90 >")
eq(gauge("hp").value, 296, "over max clamped for the bar")

-- command typed after the prompt
F.feedLine("Hp: 100/296 Sp: 120/150 Ep: 80/90 > look")
eq(gauge("hp").value, 100, "command glued after the prompt")

-- gold and exp kept
F.feedLine("Hp: 100/296 Sp: 120/150 Ep: 80/90 Gold: 50 Exp: 700 >")
eq(V.last.gold, 50, "gold kept"); eq(V.last.exp, 700, "exp kept")

-- junk ignored
local before = V.last
F.feedLine("Hp: banana"); F.feedLine("Chat: Bob says Hp: 5/5 Sp: 1/1 Ep: 1/1 >"); F.feedLine("")
F.feedLine("Hp: 1/0 Sp: 1/1 Ep: 1/1 >")
eq(V.last, before, "junk lines ignored")

-- theme colours
local T = rmgui.theme
for _, name in ipairs({ "welstar", "crypt" }) do
    T.apply(name, env, {})
    local c = T.presets[name].colors
    eq(gauge("hp").styleFront, ("background-color: rgb(%d, %d, %d); border-radius: 2px;"):format(c.hp[1], c.hp[2], c.hp[3]), name .. " hp front")
    eq(gauge("ep").styleFront:find(("rgb(%d, %d, %d)"):format(c.ep[1], c.ep[2], c.ep[3]), 1, true) ~= nil, true, name .. " ep front")
    eq(gauge("sp").styleBack:find(("rgb(%d, %d, %d)"):format(c.surface[1], c.surface[2], c.surface[3]), 1, true) ~= nil, true, name .. " back")
    eq(gauge("sp").styleText ~= nil, true, name .. " text style set")
    -- the numbers are drawn in the panel text colour, on the panel background: always readable (THEME-013)
    eq(label("hp").textColor, T.textColor("panel", T.resolve(name)), name .. " number colour is the panel text colour")
    eq(label("hp").styleSheet:find("background-color: transparent", 1, true) ~= nil, true, name .. " number label is transparent")
end
eq(gauge("hp").text.text, "100/296", "values redrawn after a theme change")

-- teardown
V.teardown(env)
eq(mod(), 0, "no gauges left")
eq(#F.triggers, 0, "no trigger left")
eq(#F.handlers, 1, "only the test's own handler left")
eq(V.last, nil, "last cleared")
V.teardown(env)
eq(mod(), 0, "teardown twice")
T.apply("welstar", env, {}) -- element gone: no raise, nothing recreated
eq(mod(), 0, "theme apply after teardown builds nothing")

-- init after teardown, twice: no duplicates
V.init(env); V.init(env)
eq(mod() > 0 and #F.triggers, 1, "re-init: one trigger")
eq(F.counts().handlers, 2, "re-init: one layout handler plus the test's")
V.teardown(env)
eq(mod(), 0, "clean after re-init")

-- slot missing, then onLayout builds
setup(false)
eq(mod(), 0, "no slot: no gauges")
F.feedLine(PROMPT)
eq(V.last.hp, 296, "prompt still tracked without gauges")
slot = Geyser.Container:new({ name = "test.slot", x = 0, y = 0, width = 200, height = 100 })
F.fire("rmgui.onLayout", { layout = "wide" })
eq(gauge("hp") ~= nil, true, "onLayout builds")
eq(gauge("hp").text.text, "296/296", "built gauges show the last values")
F.fire("rmgui.onLayout", { layout = "wide" })
eq(mod() >= 3 and F.counts().objects, #F.objectList, "second onLayout keeps the gauges")
eq(F.counts().objects, #F.objectList, "object count consistent")
V.teardown(env)
eq(mod(), 0, "teardown after late build")

-- missing layout module and failing slot lookup: no raise
setup(true)
V.teardown(env)
rmgui.layout = nil
eq(pcall(V.init, env), true, "init without layout")
eq(mod(), 0, "no gauges without layout")
V.teardown(env)
rmgui.layout = { get = function() error("boom") end }
eq(pcall(V.init, env), true, "init with failing layout.get")
V.teardown(env)
rmgui.layout = { get = layoutGet }

-- failing Geyser
slot = Geyser.Container:new({ name = "test.slot", x = 0, y = 0, width = 200, height = 100 })
F.failOn = { ["Gauge:new"] = true }
eq(pcall(V.init, env), true, "init with failing Gauge:new")
eq(mod(), 0, "nothing half built")
F.failOn = nil
F.feedLine(PROMPT)
eq(V.last.hp, 296, "tracking works after a failed build")
V.teardown(env)
F.failOn = { ["Gauge:setValue"] = true, ["Gauge:setStyleSheet"] = true }
V.init(env)
eq(pcall(F.feedLine, PROMPT), true, "failing setValue does not raise")
F.failOn = nil
V.teardown(env)
eq(mod(), 0, "clean at the end")

-- layout rebuilt: the old slot is deleted with its gauges, onLayout must rebuild in the new slot
setup(true)
local baseline = mod()
slot:delete()
slot = Geyser.Container:new({ name = "test.slot2", x = 0, y = 0, width = 200, height = 100 })
F.fire("rmgui.onLayout", { layout = "wide" })
eq(gauge("hp") and gauge("hp").parent, slot, "gauges rebuilt in the replaced slot")
eq(mod(), baseline, "no duplicate gauges after rebuild")
V.teardown(env)

-- teardown survives a raising killTrigger/killEvent and still removes the gauges
setup(true)
local bad = setmetatable({ killTrigger = function() error("x") end, killEvent = function() error("y") end }, { __index = env })
eq(pcall(V.teardown, bad), true, "teardown with raising kill functions")
eq(mod(), 0, "gauges removed anyway")
V.teardown(env)

-- init survives raising lineTrigger/registerEvent
local bad2 = setmetatable({ lineTrigger = function() error("x") end, registerEvent = function() error("y") end }, { __index = env })
eq(pcall(V.init, bad2), true, "init with raising lineTrigger and registerEvent")
V.teardown(env)
eq(mod(), 0, "clean after failed init")

if COVER then
    debug.sethook()
    local f = io.open(root .. "/src/scripts/vitals/glue.lua")
    local n = 0
    for line in f:lines() do
        n = n + 1
        local src = "@" .. root .. "/src/scripts/vitals/glue.lua"
        if not hit[src:sub(2) .. ":" .. n] and line:match("%S") and not line:match("^%s*%-%-") and not line:match("^%s*end[%s,)]*$") and not line:match("^%s*}") then
            print("not run: " .. n .. ": " .. line)
        end
    end
    f:close()
end
print(("vitals_glue: %d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
