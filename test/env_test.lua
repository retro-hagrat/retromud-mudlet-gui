-- Tests for src/scripts/core/env.lua against the fake Mudlet. Run from the repo root: lua test/env_test.lua
-- COVER=1 prints the lines of env.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local F = dofile(root .. "/test/fake_mudlet.lua")
F.reset()
dofile(root .. "/src/scripts/core/env.lua")

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

local env = rmgui.core.makeEnv()
eq(env.homeDir, "/fake/home", "homeDir")
eq(env.dirs.player, "/fake/home/retromud-gui-theme", "player dir")
eq(env.dirs.themes, "/fake/home/retromud-gui/themes", "themes dir")
eq(env.settings, nil, "settings left for the boot step"); eq(env.saveSettings, nil, "saveSettings left for the boot step")

-- say
env.say("hello", "ok"); env.say("careful", "warn"); env.say("bad", "err"); env.say("plain"); env.say("odd", "nope")
eq(F.output[1], "[rmgui] hello", "say prefix"); eq(#F.output, 5, "say lines")
eq(F.calls[#F.calls].args[1], "<grey>[rmgui] odd\n", "unknown level is grey")
local colours = {}
for _, c in ipairs(F.calls) do if c.fn == "cecho" then colours[#colours + 1] = c.args[1]:match("^<(%a+)>") end end
eq(table.concat(colours, ","), "green,yellow,red,grey,grey", "level colours")

-- files
eq(env.exists("/p/a.lua"), false, "missing file")
eq(env.save("/p/a.lua", { n = 1 }), true, "save"); eq(env.exists("/p/a.lua"), true, "exists after save")
eq(env.load("/p/a.lua").n, 1, "load")
local t, err = env.load("/p/missing.lua"); eq(t, nil, "load missing is nil"); eq(type(err), "string", "load missing has a message")
eq(select(1, env.save("/nofs/a.lua", {})), nil, "save failure is nil")

-- map colours, cmdline, border colour
setMapBackgroundColor(1, 2, 3, 4); setMapRoomExitsColor(5, 6, 7)
local bg, ex = env.mapColors.get(); eq(table.concat(bg, ","), "1,2,3,4", "map bg get"); eq(table.concat(ex, ","), "5,6,7", "map exits get")
env.mapColors.set({ 10, 20, 30, 40 }, { 50, 60, 70 })
eq(table.concat(F.mapBg, ","), "10,20,30,255", "map bg set uses first three"); eq(table.concat(F.mapExits, ","), "50,60,70", "exits set")
env.cmdline.set("x"); eq(F.cmdlineCss, "x", "cmdline css")
env.setBorderColor(1, 2, 3); eq(F.borderColor[2], 2, "border colour")

-- override file
eq(env.loadOverride(), nil, "no override file")
local n0 = #F.output
local pf = env.dirs.player .. "/theme.lua"
F.files[pf] = "return { accent = 5 }"
eq(env.loadOverride().accent, 5, "override table")
F.files[pf] = "return { g = tostring(1) }"; eq(env.loadOverride(), nil, "no globals in the override"); eq(#F.output, n0 + 1, "one message for a broken file")
F.files[pf] = "return 5"; eq(env.loadOverride(), nil, "override must be a table"); eq(F.output[#F.output]:find("must return a table", 1, true) ~= nil, true, "message says why")
F.files[pf] = "return {"; eq(env.loadOverride(), nil, "syntax error"); eq(#F.output, n0 + 3, "message per broken file")
-- Lua 5.1 style loadfile ignores the env argument, setfenv does the job
local oldLoadfile, oldSetfenv = loadfile, setfenv
local secret = "yes"
F.files[pf] = "return { v = secret }"
loadfile = function(p) return load(F.files[p], "=" .. p, "t", _G) end
setfenv = function(fn, e) debug.setupvalue(fn, 1, e) end
secret_g = nil
_G.secret = secret
eq(env.loadOverride().v, nil, "setfenv path hides globals")
loadfile, setfenv, _G.secret = oldLoadfile, oldSetfenv, nil

-- thin wrappers
local fired
local tid = env.timer(5, function() fired = true end); F.runTimers(5); eq(fired, true, "timer runs")
local tk = env.timer(5, function() fired = "no" end); eq(env.killTimer(tk), true, "killTimer")
F.setWindowSize(640, 480); local w, h = env.windowSize(); eq(w + h, 1120, "windowSize")
eq(env.charWidth(), 8, "charWidth"); F.setCharSize(9, 16); eq(env.charWidth(), 9, "charWidth follows font")
local realCalc = calcFontSize; calcFontSize = function() return nil end; eq(env.charWidth(), 8, "charWidth fallback"); calcFontSize = realCalc
eq(env.packageVersion("retromud-mapper"), nil, "no package"); F.packages["retromud-mapper"] = "0.0.4"; eq(env.packageVersion("retromud-mapper"), "0.0.4", "package version")
local realGpi = getPackageInfo; getPackageInfo = function() return {} end; eq(env.packageVersion("x"), nil, "non string version"); getPackageInfo = realGpi
F.feedLine("a line", { prompt = true }); eq(env.isPrompt(), true, "isPrompt"); eq(env.currentLine(), "a line", "currentLine")
env.expandAlias("look"); eq(F.expanded[1], "look", "expandAlias")

-- alias
local aliasHit
local aid = env.alias("^rgui (.*)$", function() aliasHit = matches[2] end)
F.sendAlias("rgui theme x"); eq(aliasHit, "theme x", "alias runs"); eq(F.counts().aliases, 1, "alias counted")
eq(env.killAlias(aid), true, "killAlias"); eq(F.counts().aliases, 0, "alias gone")

-- events
local seen
local id = env.registerEvent("e", function(_, a, b) seen = a .. b end)
env.raise("e", "x", "y"); eq(seen, "xy", "raise and register")
eq(env.killEvent(id), true, "killEvent"); eq(F.counts().handlers, 0, "no handlers left")
rmgui_probe_global = 1; env.clearGlobal("rmgui_probe_global"); eq(rmgui_probe_global, nil, "clearGlobal")

-- line trigger
local lines, boom = {}, 0
local lt = env.lineTrigger(function(l) lines[#lines + 1] = l; if l == "bad" then boom = boom + 1; error("x") end end)
F.lines("one", "bad", "two")
eq(table.concat(lines, ","), "one,bad,two", "lineTrigger sees every line, survives an error")
eq(env.killTrigger(lt), true, "killTrigger"); F.feedLine("three"); eq(#lines, 3, "trigger stays dead")

F.restore()
if COVER then
    debug.sethook()
    local src, miss = root .. "/src/scripts/core/env.lua", {}
    local n = 0
    for line in io.lines(src) do
        n = n + 1
        local code = line:gsub("%-%-.*$", "")
        if code:match("%S") and not code:match("^%s*end[%s,%)]*$") and not hit[src .. ":" .. n] and not hit["src/scripts/core/env.lua:" .. n] then miss[#miss + 1] = n end
    end
    print("lines never run: " .. table.concat(miss, " "))
end
print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
