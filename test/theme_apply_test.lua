-- Tests for src/scripts/theme/apply.lua. Run from the repo root: lua test/theme_apply_test.lua
-- COVER=1 prints the lines of apply.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
dofile(root .. "/src/scripts/theme/presets.lua")
dofile(root .. "/src/scripts/theme/logic.lua")
dofile(root .. "/src/scripts/theme/apply.lua")
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
local function anyHas(list, part, label)
    local f = false
    for _, s in ipairs(list) do if s:find(part, 1, true) then f = true end end
    eq(f, true, label)
end

local NAMES = { "welstar", "crypt", "sosel", "wysoom", "raji", "perdow" }

local function fresh()
    for _, n in ipairs({ "a", "b", "c", "x", "y" }) do T.unregister(n) end
    T.state.active, T.state.originalMap = nil, nil
end
local function mkenv(extra)
    local e = { said = {}, raised = {}, files = {}, calls = {} }
    e.say = function(m, l) e.said[#e.said + 1] = m; e.lastLevel = l end
    e.exists = function(p) return e.files[p] == true end
    e.dirs = { player = "/p/gui", themes = "/pkg/themes" }
    e.raise = function(...) e.raised[#e.raised + 1] = { ... } end
    e.map = { bg = { 1, 2, 3 }, exits = { 4, 5, 6 } }
    e.mapColors = {
        get = function() return e.map.bg, e.map.exits end,
        set = function(b, x) e.map.bg, e.map.exits = b, x; e.calls[#e.calls + 1] = "map" end,
    }
    e.setBorderColor = function(r, g, b) e.border = { r, g, b }; e.calls[#e.calls + 1] = "border" end
    e.cmdline = { set = function(css) e.cmd = css end }
    for k, v in pairs(extra or {}) do e[k] = v end
    return e
end
local ON = { mapTheming = true, cmdlineTheming = true }

---------------------------------------------------------------- register, order, isolation
fresh()
local order = {}
T.register("a", function() order[#order + 1] = "a" end)
T.register("b", function() order[#order + 1] = "b" end)
T.register("c", function() order[#order + 1] = "c" end)
eq(T.register("x", "nope"), false, "register rejects a non-function")
local e = mkenv()
local ok, rep = T.apply("crypt", e, ON)
eq(ok, true, "apply ok")
eq(table.concat(order, ""), "abc", "elements run in registration order")
T.register("b", function() order[#order + 1] = "B" end)
order = {}
T.apply("crypt", e, ON)
eq(table.concat(order, ""), "aBc", "re-register replaces in place")
eq(T.unregister("a"), true, "unregister known")
eq(T.unregister("a"), false, "unregister unknown")
order = {}
T.apply("crypt", e, ON)
eq(table.concat(order, ""), "Bc", "unregistered element not called")
T.apply("crypt", e, ON)
eq(#order, 4, "idempotence: apply twice calls elements twice (THEME-005)")

fresh()
local seen = {}
T.register("a", function() seen[#seen + 1] = "a" end)
T.register("b", function() error("boom") end)
T.register("c", function() seen[#seen + 1] = "c" end)
e = mkenv()
ok, rep = T.apply("sosel", e, ON)
eq(ok, true, "failing element does not fail apply")
eq(table.concat(seen), "ac", "failing element does not stop others")
eq(#rep.failedElements, 1, "one failed element")
eq(rep.failedElements[1], "b", "failed element named")
local n = 0
for _, m in ipairs(e.said) do if m:find("element b failed", 1, true) then n = n + 1 end end
eq(n, 1, "one say line per failed element")
eq(T.active(), "sosel", "active set despite failure")

-- element may change the registry while it runs
fresh()
T.register("a", function() T.unregister("b") end)
T.register("b", function() seen.b = true end)
seen = {}
T.apply("sosel", mkenv(), ON)
eq(seen.b, true, "snapshot of the list: removal during a run takes effect next time")

---------------------------------------------------------------- ctx
fresh()
local ctx
T.register("a", function(c) ctx = c end)
e = mkenv()
e.files["/pkg/themes/raji/panel.png"] = true
e.files["/p/gui/button.png"] = true
e.files["/pkg/themes/raji/button.png"] = true
T.apply("raji", e, ON)
eq(ctx.name, "raji", "ctx.name")
eq(ctx.theme.name, "raji", "ctx.theme resolved")
eq(ctx.image("panel"), "/pkg/themes/raji/panel.png", "theme folder image")
eq(ctx.image("button"), "/p/gui/button.png", "player image wins over theme folder")
eq(ctx.image("tab"), nil, "no image")
has(ctx.css("panel"), "border-image: url(\"/pkg/themes/raji/panel.png\")", "css uses image path")
has(ctx.css("tab"), "background-color", "css without image")
eq(ctx.css("bogus"), nil, "css of unknown role is nil")
eq(ctx.textColor("panel"), T.textColor("panel", ctx.theme), "textColor")
eq(ctx.textColor("bogus"), nil, "textColor unknown role nil")

-- a throwing exists does not stop the apply
e = mkenv({ exists = function() error("io") end })
ok = T.apply("raji", e, ON)
eq(ok, true, "throwing exists is survived")
eq(ctx.image("panel"), nil, "no image after throwing exists")

---------------------------------------------------------------- unknown theme
fresh()
local calls = 0
T.register("a", function() calls = calls + 1 end)
e = mkenv()
T.apply("crypt", e, ON)
calls = 0
e.said, e.raised = {}, {}
ok = T.apply("nonesuch", e, ON)
eq(ok, false, "unknown theme returns false")
eq(T.active(), "crypt", "old theme stays active")
eq(calls, 0, "no element called")
eq(#e.raised, 0, "no event raised")
anyHas(e.said, "unknown theme", "unknown theme said")
eq(T.apply(42, e, ON), false, "non-string name")
eq(T.apply("crypt", nil, nil), true, "nil env and settings never raise")

---------------------------------------------------------------- override and warnings
fresh()
e = mkenv({ loadOverride = function() return { colors = { accent = "red", bogus = 1, text = { 255, 255, 255 } }, imageScale = 0 } end })
ok, rep = T.apply("perdow", e, {})
eq(ok, true, "override with problems still applies")
eq(rep.problems, 3, "three problems counted")
local c1 = 0
for _, m in ipairs(e.said) do if m:find("accent", 1, true) then c1 = c1 + 1 end end
eq(c1, 1, "each problem said once")
anyHas(e.said, "bogus", "unknown key said")

e = mkenv({ loadOverride = function() error("bad file") end })
ok, rep = T.apply("perdow", e, {})
eq(ok, true, "throwing loadOverride survived")
eq(rep.problems, 1, "load error counted")
anyHas(e.said, "bad file", "load error said")
e = mkenv({ loadOverride = function() return "junk" end })
ok, rep = T.apply("perdow", e, {})
eq(rep.problems, 0, "non-table override ignored")

-- a colour override that breaks contrast warns but applies
e = mkenv({ loadOverride = function() return { colors = { text = { 40, 40, 40 }, surface = { 30, 30, 30 } } } end })
ok, rep = T.apply("perdow", e, {})
eq(ok, true, "low contrast still applies")
eq(rep.warnings > 0, true, "warnings counted")
anyHas(e.said, "low contrast", "warning said")
eq(e.lastLevel, "warn", "warning level")
eq(T.state.active, "perdow", "state set")

---------------------------------------------------------------- map and border
fresh()
e = mkenv()
T.apply("crypt", e, ON)
local want = T.resolve("crypt")
eq(e.map.bg[1], want.colors.map.background[1], "map bg set")
eq(e.map.exits[1], want.colors.map.exits[1], "map exits set")
eq(e.border[1], want.colors.surface[1], "border r")
eq(e.border[3], want.colors.surface[3], "border b")
eq(T.state.originalMap.bg[1], 1, "original map bg saved")
eq(T.state.originalMap.exits[3], 6, "original map exits saved")
T.apply("welstar", e, ON)
eq(T.state.originalMap.bg[1], 1, "originals not overwritten on later apply")
eq(T.state.originalMap.exits[1], 4, "exits originals not overwritten")
T.restore(e)
eq(e.map.bg[1], 1, "restore puts bg back")
eq(e.map.exits[1], 4, "restore puts exits back")
eq(T.active(), nil, "restore clears active")
eq(T.state.originalMap, nil, "restore clears originals")
e.calls = {}
T.restore(e)
eq(#e.calls, 0, "second restore does nothing")
T.restore(nil)
T.restore({})
eq(T.active(), nil, "restore with no env is safe")
-- restore without map members keeps no stale state
T.apply("crypt", e, ON)
T.restore({ mapColors = {} })
eq(T.state.originalMap, nil, "restore without set still clears")
-- throwing set in restore is reported
T.apply("crypt", e, ON)
e.said = {}
T.restore({ say = function(m) e.said[#e.said + 1] = m end, mapColors = { set = function() error("x") end } })
anyHas(e.said, "map colours failed", "restore set failure said")

-- apply again after restore saves originals again
e = mkenv()
T.apply("crypt", e, ON)
eq(T.state.originalMap ~= nil, true, "originals saved again after restore")

fresh()
e = mkenv()
T.apply("crypt", e, { mapTheming = false, cmdlineTheming = false })
eq(#e.calls, 0, "mapTheming=false skips map and border")
eq(e.border, nil, "no border colour")
eq(T.state.originalMap, nil, "no originals saved")
eq(e.cmd, nil, "no command line when not opted in")
T.apply("crypt", e, nil)
eq(e.cmd, nil, "nil settings: no command line")

-- throwing hooks do not break apply
fresh()
e = mkenv()
e.mapColors.set = function() error("m") end
e.setBorderColor = function() error("b") end
e.cmdline.set = function() error("c") end
e.raise = function() error("r") end
ok = T.apply("crypt", e, ON)
eq(ok, true, "throwing map, border, cmdline, raise survived")
anyHas(e.said, "map colours failed", "map failure said")
anyHas(e.said, "border colour failed", "border failure said")
anyHas(e.said, "command line style failed", "cmdline failure said")

-- map.get returning nothing saves nothing
fresh()
e = mkenv()
e.mapColors.get = function() end
T.apply("crypt", e, ON)
eq(T.state.originalMap, nil, "no originals when get returns nil")
e.mapColors.get = function() error("g") end
T.apply("crypt", e, ON)
eq(T.state.originalMap, nil, "throwing get survived")

---------------------------------------------------------------- command line and event
fresh()
e = mkenv()
T.apply("welstar", e, { cmdlineTheming = true })
local cl = T.presets.welstar.cmdline
eq(e.cmd, ("QPlainTextEdit{background-color: rgb(%d, %d, %d); color: rgb(%d, %d, %d);}"):format(
    cl.background[1], cl.background[2], cl.background[3], cl.text[1], cl.text[2], cl.text[3]), "cmdline css")
eq(#e.raised, 1, "event raised once")
eq(e.raised[1][1], "rmgui.onTheme", "event name")
eq(e.raised[1][2], "welstar", "event argument")

---------------------------------------------------------------- minimal env
fresh()
for _, env in ipairs({ {}, { dirs = {} }, { dirs = { player = "x" }, exists = function() return false end } }) do
    local o = T.apply("crypt", env, ON)
    eq(o, true, "missing optional env members never raise")
end
eq(T.apply("crypt", { say = function() error("s") end, loadOverride = function() error("e") end }, ON), true, "throwing say survived")

---------------------------------------------------------------- all presets
for _, nm in ipairs(NAMES) do
    fresh()
    e = mkenv()
    ok, rep = T.apply(nm, e, ON)
    eq(ok, true, "preset applies: " .. nm)
    eq(rep.problems, 0, "no problems: " .. nm)
    eq(rep.warnings, 0, "no warnings: " .. nm)
    eq(#e.said, 0, "nothing said: " .. nm)
end

---------------------------------------------------------------- list, active
local l = T.list()
eq(#l, 6, "list has six")
eq(l[1].name, "crypt", "list sorted: first")
eq(l[6].name, "wysoom", "list sorted: last")
eq(l[1].title, T.presets.crypt.title, "list title")
eq(l[1].description, T.presets.crypt.description, "list description")

---------------------------------------------------------------- command
fresh()
local st = {}
e = mkenv()
local r1, r2 = T.command("", e, st)
eq(r1, true, "empty command ok")
eq(r2, false, "empty command changes nothing")
has(e.said[1], "none", "empty shows no active theme")
eq(#e.said, 7, "empty shows active line and six themes")
e.said = {}
T.command("list", e, st)
eq(#e.said, 6, "list shows six")
e.said = {}
r1, r2 = T.command("reload", e, st)
eq(r1, false, "reload without active theme")
has(e.said[1], "no theme", "reload message")
r1, r2 = T.command("  CrYpT  ", e, st)
eq(r1, true, "apply by name, trimmed, case-insensitive")
eq(r2, true, "settings changed")
eq(st.theme, "crypt", "settings.theme set")
eq(T.active(), "crypt", "active after command")
e.said = {}
T.command(nil, e, st)
has(e.said[1], "crypt", "empty shows the active theme")
calls = 0
T.register("a", function() calls = calls + 1 end)
r1, r2 = T.command("reload", e, st)
eq(r1, true, "reload ok")
eq(r2, false, "reload changes no settings")
eq(calls, 1, "reload calls elements")
e.said = {}
r1, r2 = T.command("narnia", e, st)
eq(r1, false, "unknown name fails")
eq(r2, false, "unknown name changes nothing")
eq(st.theme, "crypt", "settings untouched")
has(e.said[1], "rgui theme list", "suggests rgui theme list")
eq(T.active(), "crypt", "old theme still active")
r1, r2 = T.command("sosel", nil, nil)
eq(r1, true, "command with nil env and settings")
eq(r2, false, "no settings table, nothing changed")
r1 = T.command("reload", nil, nil)
eq(r1, true, "reload with nil env")

-- regression: fractional or NaN override colours must not make apply raise
do
    fresh()
    local e = mkenv()
    local ov = { cmdline = { background = { 10.5, 0, 0 }, text = { 0 / 0, 0, 0 } } }
    e.loadOverride = function() return ov end
    local ok, r = pcall(T.apply, "welstar", e, ON)
    eq(ok and r, true, "fractional cmdline colour does not raise")
    eq(T.active(), "welstar", "active set after fractional colour")
    eq(e.cmd ~= nil, true, "cmdline still set")
    eq(e.raised[1] and e.raised[1][1], "rmgui.onTheme", "event raised after fractional colour")
end

if COVER then
    debug.sethook()
    local path = root .. "/src/scripts/theme/apply.lua"
    local k = 0
    for line in io.lines(path) do
        k = k + 1
        local code = line:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$") or code:match("^local function")
            or code:match("^function ") or code:match("^[%]})]+,?$") or code:match("^elseif") or code:match("^}$")
        if not skip and not hit[path .. ":" .. k] then print(("not run  apply.lua:%d  %s"):format(k, code)) end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
