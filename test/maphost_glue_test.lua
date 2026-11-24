-- Tests for src/scripts/maphost/glue.lua. Run from the repo root: lua test/maphost_glue_test.lua
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local F = dofile(root .. "/test/fake_mudlet.lua")

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

local elements, slot, mapExists
local function world(opts)
    opts = opts or {}
    F.reset()
    rmgui, rmap = nil, nil
    elements = {}
    mapExists = false
    dofile(root .. "/src/scripts/core/lifecycle.lua")
    dofile(root .. "/src/scripts/core/env.lua")
    rmgui.theme = {
        register = function(n, fn) elements[n] = fn return true end,
        unregister = function(n) elements[n] = nil return true end,
    }
    slot = Geyser.Container:new({ name = "slot" })
    rmgui.layout = { get = function(s) if s == "map" and not opts.noSlot then return slot end end }
    Geyser.windowList = F.objects
    dofile(root .. "/src/scripts/maphost/glue.lua")
    local env = rmgui.core.makeEnv()
    env.say = function() end
    if not opts.noHasMap then env.hasMap = function() return mapExists end end
    return env
end
local function theme()
    elements["maphost.placeholder"]({ css = function(r) return "css-" .. r end, textColor = function(r) return "col-" .. r end })
end
local function O(n) return F.objects["rmgui.maphost." .. n] end
local function pristine(label)
    local c = F.counts()
    eq(c.objects + c.handlers + c.timers + c.triggers, 1, label .. " (only the test slot left)")
end

-- placeholder until the map exists, then the fallback mapper
local env = world()
rmgui.maphost.init(env)
eq(O("placeholder") ~= nil, true, "placeholder shown")
eq(O("mapper"), nil, "no mapper yet")
eq(O("placeholder").text, "no map yet - type rmap start", "placeholder text")
theme()
eq(O("placeholder").styleSheet, "css-panel", "placeholder css")
eq(O("placeholder").textColor, "col-tab", "placeholder colour")
F.fire("rmap.onRoom", {})
eq(O("mapper"), nil, "still no map")
mapExists = true
F.fire("rmap.onMoved", 1, "room", "area")
eq(O("mapper") ~= nil, true, "mapper after onMoved")
eq(O("placeholder"), nil, "placeholder gone")
eq(O("mapper").parent, slot, "mapper in slot")
eq(O("mapper").width, "100%", "mapper fills slot")
F.fire("rmap.onRoom", {})
eq(#slot.children, 1, "no second mapper")
local raises = 0
O("mapper").raise = function() raises = raises + 1 end
F.fire("rmgui.onLayout")
eq(raises, 1, "a layout event raises the map above the panel labels")
theme()
eq(raises, 2, "a theme change raises the map too")
rmgui.maphost.teardown()
pristine("fallback teardown")
rmgui.maphost.teardown()
pristine("teardown twice")
eq(elements["maphost.placeholder"], nil, "theme unregistered")
rmgui.maphost.init(env)
rmgui.maphost.init(env)
eq(#slot.children, 1, "init twice, no duplicates")
rmgui.maphost.teardown()

-- hasMap missing or failing counts as true
env = world({ noHasMap = true })
rmgui.maphost.init(env)
eq(O("mapper") ~= nil, true, "no hasMap -> mapper")
rmgui.maphost.teardown()
env.hasMap = function() error("x") end
rmgui.maphost.init(env)
eq(O("mapper") ~= nil, true, "failing hasMap -> mapper")
rmgui.maphost.teardown()

-- adopt path
env = world()
local pane = Geyser.Container:new({ name = "rmap.map", width = 50 })
rmap = { api = { container = function() return "rmap.map" end } }
rmgui.maphost.init(env)
eq(pane.parent, slot, "adopted into slot")
eq(pane.width, "100%", "adopted fills slot")
eq(O("mapper"), nil, "no fallback when adopted")
eq(O("placeholder"), nil, "no placeholder when adopted")
F.fire("rmap.onRoom", {})
eq(#slot.children, 1, "adopted once")
rmgui.maphost.teardown()
eq(F.objects["rmap.map"], pane, "adopted container survives teardown")
eq(pane.parent ~= slot, true, "given back")
eq(pane.parent, Geyser, "given back to root")
eq(#slot.children, 0, "slot empty")

-- adopt after fallback was built
env = world()
rmap = nil
mapExists = true
rmgui.maphost.init(env)
eq(O("mapper") ~= nil, true, "fallback first")
pane = Geyser.Container:new({ name = "rmap.map" })
rmap = { api = { container = function() return "rmap.map" end } }
F.fire("rmap.onRoom", {})
eq(O("mapper"), nil, "fallback replaced")
eq(pane.parent, slot, "adopted later")
rmgui.maphost.teardown()

-- the mapper announces its pane: adopt at once, with no room event
env = world()
rmap = nil
mapExists = true
rmgui.maphost.init(env)
pane = Geyser.Container:new({ name = "rmap.map" })
rmap = { api = { container = function() return "rmap.map" end } }
F.fire("rmap.onUiReady", "rmap.map")
eq(pane.parent, slot, "adopted on onUiReady")
eq(O("mapper"), nil, "fallback replaced on onUiReady")
rmgui.maphost.teardown()

-- name unknown, not a string, or adopt raising: fallback
for _, c in ipairs({ function() return "nope" end, function() return nil end, function() error("x") end }) do
    env = world()
    mapExists = true
    rmap = { api = { container = c } }
    rmgui.maphost.init(env)
    eq(O("mapper") ~= nil, true, "fallback when container unusable")
    rmgui.maphost.teardown()
end
env = world()
mapExists = true
Geyser.Container:new({ name = "rmap.map" })
F.failOn = { ["Container:resize"] = true }
rmap = { api = { container = function() return "rmap.map" end } }
rmgui.maphost.init(env)
F.failOn = nil
eq(O("mapper") ~= nil, true, "fallback when adopt fails")
rmgui.maphost.teardown()

-- mapper missing: rmap without api; windowList missing
env = world()
rmap = {}
Geyser.windowList = nil
rmgui.maphost.init(env)
eq(O("placeholder") ~= nil, true, "rmap without api: placeholder")
rmgui.maphost.teardown()

-- missing slot, built on layout event
env = world({ noSlot = true })
rmgui.maphost.init(env)
eq(F.counts().objects, 1, "nothing built without slot")
rmgui.layout.get = function() return slot end
F.fire("rmgui.onLayout", { layout = "wide" })
eq(O("placeholder") ~= nil, true, "built on layout event")
rmgui.layout.get = function() error("x") end
rmgui.maphost.teardown()
pristine("after late build")

-- failing Geyser, failing registerEvent
env = world()
F.failOn = { ["Label:new"] = true, ["Mapper:new"] = true }
rmgui.maphost.init(env)
mapExists = true
F.fire("rmap.onRoom", {})
eq(F.counts().objects, 1, "failing Geyser")
rmgui.maphost.teardown()
F.failOn = nil
env.registerEvent = function() error("no") end
rmgui.maphost.init(env)
eq(F.counts().handlers, 0, "registerEvent failing")
rmgui.maphost.teardown()


-- re-running the script file while live must not leak the old instance
env = world(); rmgui.maphost.init(env)
local before = F.counts()
dofile(root .. "/src/scripts/maphost/glue.lua")
local after = F.counts()
eq(after.objects, before.objects, "reload: no duplicate objects")
eq(after.handlers, before.handlers, "reload: no duplicate handlers")
rmgui.maphost.teardown()
pristine("reload then teardown")
F.restore()
print(("maphost_glue: %d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
