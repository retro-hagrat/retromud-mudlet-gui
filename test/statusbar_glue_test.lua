-- Tests for src/scripts/statusbar/glue.lua. Run from the repo root: lua test/statusbar_glue_test.lua
-- COVER=1 prints the lines of glue.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local FM = dofile(root .. "/test/fake_mudlet.lua")
FM.reset()
for _, f in ipairs({ "core/lifecycle", "core/env", "theme/presets", "theme/logic", "theme/apply",
    "statusbar/format", "statusbar/glue" }) do
    dofile(root .. "/src/scripts/" .. f .. ".lua")
end
local S = rmgui.statusbar

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

local env, said
local function world(opts)
    opts = opts or {}
    if rmgui.statusbar.teardown then S.teardown() end
    FM.reset()
    rmap = opts.rmap
    rmgui.layout = nil
    if not opts.noSlot then
        local top = Geyser.Container:new({ name = "slot.top", x = 0, y = 0, width = 400, height = 20 })
        rmgui.layout = { get = function(slot) return slot == "top" and top or nil end }
    end
    if opts.mapper ~= false then FM.packages.retromud = "1.0" end
    env = rmgui.core.makeEnv()
    said = {}
    env.say = function(m) said[#said + 1] = m end
    FM.failOn = opts.failOn
    S.init(env)
    FM.failOn = nil
end
local function lbl() return FM.objects["rmgui.statusbar.label"] end
local function text() return lbl() and lbl().text end
local function mine(c) return c.objects == 0 and c.triggers == 0 and c.timers == 0 and c.handlers == 0 end

-- mapper installed, nothing known yet
world()
eq(text(), "no room yet", "initial text")
eq(lbl().textColor, nil, "no colour before the first theme call")
eq(lbl():get_width(), 400, "label fills the top slot")

-- onRoom fallback until the first onMoved
FM.fire("rmap.onRoom", { name = "Mirel Hall" })
eq(text(), "Mirel Hall", "onRoom sets the room")
FM.fire("rmap.onRoom", "junk")
eq(text(), "Mirel Hall", "bad onRoom payload ignored")
FM.fire("rmap.onMoved", 7, "Bran Keep Gate", "Bran Keep")
eq(text(), "Bran Keep Gate", "onMoved sets the room")
FM.fire("rmap.onRoom", { name = "Other" })
eq(text(), "Bran Keep Gate", "onRoom ignored after onMoved")

-- mapping and state
FM.fire("rmap.onState", "SYNCED")
eq(text(), "Bran Keep Gate", "area hidden while mapping is off")
FM.fire("rmap.onMapping", true)
eq(text(), "Bran Keep Gate  Bran Keep  [SYNCED]", "mapping on shows area and state")
FM.fire("rmap.onState", "PENDING")
eq(text(), "Bran Keep Gate  Bran Keep  [PENDING]", "state change redraws")
FM.fire("rmap.onMapping", false)
eq(text(), "Bran Keep Gate", "mapping off hides area")

-- truncation by width
FM.fire("rmap.onMapping", true)
FM.fire("rmap.onState", "SYNCED")
lbl().width = 160 -- 20 chars at 8 px
FM.fire("rmap.onState", "SYNCED")
eq(text(), "Bran Keep Gate", "long parts dropped to fit")
lbl().width = 64
FM.fire("rmap.onState", "SYNCED")
eq(text(), "Bran ...", "room name cut with dots")

-- theme change redraws with the colour
lbl().width = 400
rmgui.theme.apply("perdow", env, {})
local c1 = lbl().textColor
eq(type(c1), "string" and "string", "colour after theme call")
eq(lbl().styleSheet ~= nil, true, "stylesheet applied")
eq(lbl().styleSheet:find("border-image", 1, true), nil, "the label does not repeat the bar image")
eq(lbl().styleSheet:find("border-width", 1, true), nil, "the label has no image border that eats the text room")
eq(lbl().styleSheet:find("background-color: transparent", 1, true) ~= nil, true, "the label background is transparent")
eq(lbl().styleSheet:find("color: #", 1, true) ~= nil, true, "the label text colour is set")
rmgui.theme.apply("crypt", env, {})
eq(lbl().textColor ~= c1, true, "other theme, other colour")
FM.fire("rmap.onState", "UNSYNCED")
eq(lbl().textColor ~= nil, true, "later redraw keeps the colour")

-- mapper installed later flips the text
world({ mapper = false })
eq(text(), "no room yet  (mapper not installed)", "mapper missing text")
FM.packages.retromud = "1.0"
FM.fire("sysInstallPackage", "retromud")
eq(text(), "no room yet", "install flips the text")
FM.packages.retromud = nil
FM.fire("sysUninstallPackage", "retromud")
eq(text(), "no room yet  (mapper not installed)", "uninstall flips it back")

-- seeding from rmap.api
world({ rmap = { api = {
    state = function() return "SYNCED" end,
    position = function() return 3, "Dusk Road", "Wysoom" end,
    isMapping = function() return true end,
} } })
eq(text(), "Dusk Road  Wysoom  [SYNCED]", "first state read from rmap.api")
FM.fire("rmap.onRoom", { name = "Ignored" })
eq(text(), "Dusk Road  Wysoom  [SYNCED]", "api position counts as moved")
world({ rmap = { api = {
    state = function() error("boom") end,
    position = function() error("boom") end,
    isMapping = function() error("boom") end,
} } })
eq(text(), "no room yet", "failing api calls leave defaults")
world({ rmap = { api = {
    state = function() return 5 end,
    position = function() return 1, nil end,
    isMapping = function() return false end,
} } })
eq(text(), "no room yet", "odd api values ignored")
world({ rmap = {} })
eq(text(), "no room yet", "rmap without api is fine")

-- errors: handler never raises, said once per distinct error
world()
FM.failOn = { ["Label:echo"] = true }
local ok = pcall(FM.fire, "rmap.onState", "SYNCED")
FM.fire("rmap.onState", "PENDING")
FM.failOn = nil
eq(ok, true, "handler does not raise")
eq(#said, 1, "same error said once")

-- failing Label:new, missing slots, onLayout builds later
world({ failOn = { ["Label:new"] = true } })
eq(lbl(), nil, "no label when Geyser fails")
eq(#said, 1, "failure reported")
world({ noSlot = true })
eq(lbl(), nil, "no label without slot")
local top = Geyser.Container:new({ name = "slot.top", x = 0, y = 0, width = 400, height = 20 })
rmgui.layout = { get = function() return top end }
FM.fire("rmgui.onLayout", { layout = "wide" })
eq(text(), "no room yet", "onLayout builds the label")
FM.fire("rmgui.onLayout", { layout = "wide" })
eq(FM.counts().objects, 2, "second onLayout makes no duplicate")
rmgui.layout = { get = function() error("no layout") end }
S.teardown()
world({ noSlot = true })
rmgui.layout = { get = function() error("no layout") end }
FM.fire("rmgui.onLayout", {})
eq(lbl(), nil, "raising layout.get does not raise")

-- theme before the label exists is kept
world({ noSlot = true })
rmgui.theme.apply("perdow", env, {})
rmgui.layout = { get = function() return Geyser.Container:new({ name = "slot.top", x = 0, y = 0, width = 400, height = 20 }) end }
FM.fire("rmgui.onLayout", {})
eq(lbl().styleSheet ~= nil and lbl().textColor ~= nil, true, "late label gets the theme")

-- teardown
S.teardown()
eq(#FM.handlers, 0, "no handlers left")
eq(FM.objects["rmgui.statusbar.label"], nil, "label gone")
eq(#rmgui.theme.list() > 0, true, "theme list still fine")
local before = FM.counts().objects
S.teardown()
eq(FM.counts().objects, before, "teardown twice")
FM.fire("rmap.onState", "SYNCED")
eq(FM.counts().handlers, 0, "events after teardown do nothing")
world()
S.teardown()
S.init(env)
eq(FM.counts().handlers, 7, "init after teardown, 7 handlers")
S.init(env)
eq(FM.counts().handlers, 7, "double init does not duplicate handlers")
eq(#FM.objectList - 1, 1, "double init does not duplicate the label (plus the slot)")
S.teardown()
eq(FM.counts().handlers, 0, "clean at the end")
rmgui.theme.apply("perdow", env, {})
eq(FM.counts().objects, 1, "theme apply after teardown touches nothing (only the slot is left)")

-- through core.start / core.stop
world()
S.teardown()
rmgui.core.start(env)
eq(lbl() ~= nil, true, "core.start inits the module")
rmgui.core.stop(env)
eq(lbl(), nil, "core.stop tears it down")

-- regression: onLayout after a resize redraws to the new width
world()
FM.fire("rmap.onMapping", true); FM.fire("rmap.onState", "SYNCED")
FM.fire("rmap.onMoved", 1, "Bran Keep Gate", "Bran Keep")
lbl().width = 64
FM.fire("rmgui.onLayout", {})
eq(text(), "Bran ...", "onLayout redraws at the new width")
lbl().width = 0
FM.fire("rmgui.onLayout", {})
eq(text(), "Bran Keep Gate  Bran Keep  [SYNCED]", "width 0 (not laid out) does not truncate")

-- regression: layout rebuilt -> label in a dead parent is replaced
world()
local old = lbl()
local top2 = Geyser.Container:new({ name = "slot.top2", x = 0, y = 0, width = 300, height = 20 })
rmgui.layout = { get = function() return top2 end }
FM.fire("rmgui.onLayout", {})
eq(lbl() ~= old and lbl().parent == top2, true, "label rebuilt in the new slot")
eq(FM.counts().objects, 3, "no extra label (two slots plus one label)")

-- regression: failing charWidth does not stop the text
world()
env.charWidth = function() error("no font") end
FM.fire("rmap.onState", "SYNCED")
FM.fire("rmap.onMoved", 1, "Mirel Hall", "x")
eq(text(), "Mirel Hall", "text drawn although charWidth raises")

-- regression: file executed again while the module is live
world()
FM.fire("rmap.onMoved", 1, "Mirel Hall", "x")
dofile(root .. "/src/scripts/statusbar/glue.lua")
eq(FM.counts().handlers, 7, "rerun: no leaked handlers")
eq(#FM.objectList, 2, "rerun: one label plus the slot")
FM.fire("rmap.onMoved", 2, "Dusk Road", "x")
eq(text(), "Dusk Road", "rerun: new instance answers events")
S.teardown()
eq(FM.counts().handlers + FM.counts().objects, 1, "rerun: teardown clean (slot left)")
dofile(root .. "/src/scripts/statusbar/glue.lua")
eq(FM.counts().handlers, 0, "rerun after teardown does not start the module")

if COVER then
    debug.sethook()
    local src = io.open(root .. "/src/scripts/statusbar/glue.lua"):read("*a")
    local n = 0
    for line in (src .. "\n"):gmatch("(.-)\n") do
        n = n + 1
        if not hit[("%s/src/scripts/statusbar/glue.lua:%d"):format(root, n)] and not line:match("^%s*%-%-") and not line:match("^%s*$")
            and not line:match("^%s*end[%s%)%},]*$") and not line:match("^%s*else%s*$") then
            print("not run: " .. n .. ": " .. line)
        end
    end
end
print(("statusbar_glue: %d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
