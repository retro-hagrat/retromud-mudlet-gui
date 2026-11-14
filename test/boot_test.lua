-- Full boot against the fake Mudlet: loads every script in scripts.json order. Run: lua test/boot_test.lua
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

local function readList(path)
    local f = assert(io.open(path)); local s = f:read("a"); f:close()
    local t = {}
    for name in s:gmatch('"name":%s*"([^"]+)"') do t[#t + 1] = name end
    return t
end
local function load()
    for _, d in ipairs(readList(root .. "/src/scripts/scripts.json")) do
        for _, f in ipairs(readList(root .. "/src/scripts/" .. d .. "/scripts.json")) do
            dofile(root .. "/src/scripts/" .. d .. "/" .. f .. ".lua")
        end
    end
end
local function names()
    local n = 0
    for k in pairs(F.objects) do if tostring(k):find("^rmgui%.") then n = n + 1 end end
    return n
end

F.reset(); rmgui = nil
-- Mudlet runs Lua 5.1: these do not exist there
math.tointeger, math.type = nil, nil
F.packages["retromud-gui"] = "0.0.1"
setMapBackgroundColor(1, 2, 3); setMapRoomExitsColor(4, 5, 6)
load()
local st = rmgui.core.state()
eq(st.started, true, "started at load"); eq(#st.failed, 0, "no failed module"); eq(st.order[#st.order], "boot", "boot is last")
eq(F.counts().aliases, 4, "four aliases"); eq(rmgui.theme.state.active, "wood", "default theme applied")
eq(names() > 5, true, "objects built"); eq(F.objects["rmgui.chat.console.all"] ~= nil, true, "chat console built without math.tointeger")

F.sendAlias("rgui theme raji"); eq(rmgui.theme.state.active, "raji", "theme alias"); eq(rmgui.boot.env.settings.theme, "raji", "theme setting changed")
eq(F.files[F.home .. "/retromud-gui-settings.lua"].theme, "raji", "theme saved")
local function lines(t) local n = 0 for _ in t:gmatch("[^\n]+") do n = n + 1 end return n end
F.output = {}; F.sendAlias("rgui")
eq(F.output[1]:find("^%[rmgui%] RetroMUD GUI") ~= nil, true, "rgui alone shows the help title")
eq(lines(F.output[1]), 7, "help has a title and six commands")
eq(F.output[1]:find("rgui help", 1, true) ~= nil, true, "help lists rgui help")
F.output = {}; F.sendAlias("rgui help"); eq(lines(F.output[1] or ""), 7, "rgui help shows the help too")
F.sendAlias("rgui layout compact"); eq(rmgui.boot.env.settings.layout.mode, "compact", "layout alias")
F.fire("sysLoadEvent"); eq(rmgui.core.state().started, true, "later sysLoadEvent harmless")

eq(table.concat(F.mapBg, ",") ~= "1,2,3,255", true, "map recoloured")
F.fire("sysUninstallPackage", "other"); eq(rmgui ~= nil, true, "other package ignored")
F.fire("sysUninstallPackage", "retromud-gui")
eq(rmgui, nil, "global cleared"); eq(table.concat(F.mapBg, ",") .. "|" .. table.concat(F.mapExits, ","), "1,2,3,255|4,5,6", "map colours restored")
local c = F.counts()
eq(c.objects + c.triggers + c.timers + c.handlers + c.aliases, 0, "nothing left behind")
eq(table.concat({ F.borders.top, F.borders.right, F.borders.bottom, F.borders.left }, ","), "0,0,0,0", "borders restored")

-- second install is clean; a broken command does not raise
load()
eq(rmgui.core.state().started, true, "second install starts"); eq(rmgui.boot.env.settings.theme, "raji", "settings survive")
rmgui.theme.command = function() error("boom") end
F.sendAlias("rgui theme x"); eq(F.output[#F.output]:find("command failed", 1, true) ~= nil, true, "failing command reported")
eq(rmgui.boot.env.saveSettings(), true, "saveSettings ok")
F.fire("sysUninstallPackage", "retromud-gui")
c = F.counts(); eq(c.objects + c.triggers + c.timers + c.handlers + c.aliases, 0, "clean again")

F.restore()
print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
