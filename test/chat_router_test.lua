-- Tests for src/scripts/chat/router.lua. Run from the repo root: lua test/chat_router_test.lua
-- COVER=1 prints the lines of router.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
dofile(root .. "/src/scripts/chat/rules.lua")
dofile(root .. "/src/scripts/chat/engine.lua")
dofile(root .. "/src/scripts/chat/router.lua")
local C = rmgui.chat

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function tabs(m) return table.concat(C.tabsFor(m), ",") end

local ids = {}
for _, t in ipairs(C.TABS) do ids[#ids + 1] = t.id .. (t.lazy and "*" or "") end
eq(table.concat(ids, ","), "all,chat,world,party,info,wizard*,guild,tells", "tab order and lazy flag")
local titles = {}
for _, t in ipairs(C.TABS) do titles[#titles + 1] = t.title end
eq(table.concat(titles, ","), "All,Chat,World,Party,Info,Wizard,Guild,Tells", "tab titles")

local cases = {
    { "chat", "chat", "chat" }, { "world", "world", "world" }, { "party", "party", "party" },
    { "info", "info", "info" }, { "alert", "alert", "info" }, { "wizard", "wiz", "wizard" },
    { "guild", "fighter", "guild" }, { "tells", "tell", "tells" },
}
for _, c in ipairs(cases) do
    local m = { group = c[1], channel = c[2] }
    eq(tabs(m), "all," .. c[3], "route " .. c[1])
    -- the game line already names its channel, so no tab adds a prefix (it showed the channel twice)
    eq(C.prefixFor(m, "all"), "", "no prefix on all for " .. c[1])
    eq(C.prefixFor(m, c[3]), "", "no prefix on the own tab for " .. c[1])
end
eq(tabs({ group = "mystery" }), "all", "unknown group goes to all only")
eq(tabs(nil), "all", "nil message goes to all only")
eq(C.prefixFor({ group = "chat", channel = "retro" }, "world"), "", "foreign tab has no prefix")

-- with the real engine
local e = C.newEngine()
e:feed("Aldric [mentor]: hi")
eq(tabs(e.pending), "all,chat", "engine message routes")

if COVER then
    debug.sethook()
    local path = root .. "/src/scripts/chat/router.lua"
    local n = 0
    for l in io.lines(path) do
        n = n + 1
        local code = l:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^[%]})]+,?$") or code:match("^function ")
        if not skip and not hit[path .. ":" .. n] then print(("not run  router.lua:%d  %s"):format(n, code)) end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
