-- Tests for src/scripts/core/settings.lua. Run from the repo root: lua test/settings_test.lua
-- COVER=1 prints the lines of settings.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
dofile(root .. "/src/scripts/core/settings.lua")
local S = rmgui.settings

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function problemsMention(problems, part, label)
    local found = false
    for _, p in ipairs(problems) do if p:find(part, 1, true) then found = true end end
    eq(found, true, label)
end

---------------------------------------------------------------- defaults
local d = S.defaults()
eq(d.version, 1, "default version")
eq(d.theme, "perdow", "default theme")
eq(d.mapTheming, true, "default mapTheming")
eq(d.cmdlineTheming, false, "default cmdlineTheming")
eq(d.layout.mode, "auto", "default layout mode")
eq(d.layout.chatWidth, nil, "chatWidth unset")
eq(d.chat.maxLines, 2000, "default maxLines")
for _, k in ipairs({ "chat", "world", "wizard", "info", "alert", "guild", "party", "tells" }) do
    eq(d.chat.keepInMain[k], true, "keepInMain default " .. k)
end
d.chat.keepInMain.chat = false
d.layout.mode = "wide"
d.theme = "x"
local d2 = S.defaults()
eq(d2.chat.keepInMain.chat, true, "defaults are fresh: keepInMain")
eq(d2.layout.mode, "auto", "defaults are fresh: layout")
eq(d2.theme, "perdow", "defaults are fresh: theme")

---------------------------------------------------------------- merge
local m, p = S.merge({})
eq(#p, 0, "empty table has no problems")
eq(m.theme, "perdow", "empty table gives defaults")

for _, bad in ipairs({ "text", 5, true }) do
    m, p = S.merge(bad)
    eq(#p, 1, "non-table input: one problem " .. tostring(bad))
    eq(m.theme, "perdow", "non-table input gives defaults")
end
m, p = S.merge(nil)
eq(#p, 1, "nil input: one problem")

local saved = {
    version = 1, theme = "crypt", mapTheming = false, cmdlineTheming = true,
    layout = { mode = "compact", chatWidth = 300, sideWidth = 150.5, topHeight = 40 },
    chat = { maxLines = 500, keepInMain = { tells = false, guild = false } },
}
m, p = S.merge(saved)
eq(#p, 0, "full valid table: no problems")
eq(m.theme, "crypt", "theme merged")
eq(m.mapTheming, false, "mapTheming merged")
eq(m.cmdlineTheming, true, "cmdlineTheming merged")
eq(m.layout.mode, "compact", "mode merged")
eq(m.layout.chatWidth, 300, "chatWidth merged")
eq(m.layout.sideWidth, 150.5, "sideWidth merged")
eq(m.layout.topHeight, 40, "topHeight merged")
eq(m.chat.maxLines, 500, "maxLines merged")
eq(m.chat.keepInMain.tells, false, "keepInMain tells merged")
eq(m.chat.keepInMain.guild, false, "keepInMain guild merged")
eq(m.chat.keepInMain.world, true, "keepInMain untouched key stays default")
eq(saved.chat.keepInMain.world, nil, "caller input not mutated")
eq(m ~= saved and m.layout ~= saved.layout, true, "result is a new table")

-- partial
m, p = S.merge({ layout = { mode = "wide" }, theme = "raji" })
eq(#p, 0, "partial: no problems")
eq(m.layout.mode, "wide", "partial layout mode")
eq(m.theme, "raji", "partial theme")
eq(m.chat.maxLines, 2000, "partial keeps default maxLines")

-- unknown keys
m, p = S.merge({ colour = "red", [7] = 1, layout = { depth = 3 }, chat = { speed = 1, keepInMain = { mirel = true } } })
eq(#p, 5, "five unknown keys reported")
problemsMention(p, "colour", "unknown top key named")
problemsMention(p, "7", "non-string top key named")
problemsMention(p, "layout.depth", "unknown layout key named")
problemsMention(p, "chat.speed", "unknown chat key named")
problemsMention(p, "chat.keepInMain.mirel", "unknown keepInMain key named")
eq(m.chat.keepInMain.mirel, nil, "unknown keepInMain key not kept")
eq(m.colour, nil, "unknown key not kept")

-- wrong types and values, one problem each
local cases = {
    { { theme = 5 }, "theme" }, { { theme = "" }, "theme" },
    { { mapTheming = "yes" }, "mapTheming" }, { { cmdlineTheming = 1 }, "cmdlineTheming" },
    { { layout = { mode = "huge" } }, "layout.mode" }, { { layout = { mode = 1 } }, "layout.mode" },
    { { layout = { chatWidth = 0 } }, "layout.chatWidth" }, { { layout = { sideWidth = -3 } }, "layout.sideWidth" },
    { { layout = { topHeight = "9" } }, "layout.topHeight" }, { { layout = { topHeight = 0 / 0 } }, "layout.topHeight" },
    { { layout = { chatWidth = math.huge } }, "layout.chatWidth" },
    { { chat = { maxLines = "9" } }, "chat.maxLines" }, { { chat = { keepInMain = { tells = "no" } } }, "chat.keepInMain.tells" },
    { { layout = "wide" }, "layout" }, { { chat = 5 }, "chat" }, { { chat = { keepInMain = 5 } }, "chat.keepInMain" },
}
for i, c in ipairs(cases) do
    m, p = S.merge(c[1])
    eq(#p, 1, "wrong type case " .. i .. ": one problem")
    problemsMention(p, c[2], "wrong type case " .. i .. ": names path")
    eq(m.theme, "perdow", "wrong type case " .. i .. ": defaults kept")
end
m = S.merge({ theme = 5, chat = { keepInMain = { tells = "no" } } })
eq(m.theme, "perdow", "bad theme ignored")
eq(m.chat.keepInMain.tells, true, "bad keepInMain value ignored")

-- maxLines boundaries
for _, c in ipairs({ { 99, false }, { 100, true }, { 20000, true }, { 20001, false }, { 100.5, false }, { 500.0, true }, { 0 / 0, false } }) do
    m, p = S.merge({ chat = { maxLines = c[1] } })
    eq(#p == 0, c[2], "maxLines " .. tostring(c[1]) .. " accepted=" .. tostring(c[2]))
    eq(m.chat.maxLines == c[1], c[2], "maxLines " .. tostring(c[1]) .. " applied=" .. tostring(c[2]))
end

---------------------------------------------------------------- path
eq(S.path("/home/aldric/.config/mudlet"), "/home/aldric/.config/mudlet/retromud-gui-settings.lua", "path unix")
eq(S.path("C:\\Users\\Aldric\\mudlet"), "C:/Users/Aldric/mudlet/retromud-gui-settings.lua", "path windows")
eq(S.path(nil), nil, "path nil")
eq(S.path(5), nil, "path number")

---------------------------------------------------------------- load / save
local function fakeEnv()
    local files, env = {}, { homeDir = "/home/bran" }
    env.files = files
    env.exists = function(path) return files[path] ~= nil end
    env.load = function(path) return files[path] end
    env.save = function(path, tbl) files[path] = tbl return true end
    return env
end
local FILE = "/home/bran/retromud-gui-settings.lua"

local env = fakeEnv()
m, p = S.load(env)
eq(#p, 0, "missing file: no problem")
eq(m.theme, "perdow", "missing file: defaults")

-- round trip
local want = S.defaults()
want.theme = "welstar"
want.layout.mode = "wide"
want.layout.topHeight = 60
want.chat.maxLines = 3000
want.chat.keepInMain.alert = false
eq(S.save(env, want), true, "save ok")
eq(env.files[FILE] ~= want, true, "saved copy is not the caller table")
m, p = S.load(env)
eq(#p, 0, "round trip: no problems")
eq(m.theme, "welstar", "round trip theme")
eq(m.layout.mode, "wide", "round trip mode")
eq(m.layout.topHeight, 60, "round trip topHeight")
eq(m.chat.maxLines, 3000, "round trip maxLines")
eq(m.chat.keepInMain.alert, false, "round trip keepInMain")

-- corrupt
env = fakeEnv()
env.files[FILE] = true
env.load = function() return nil, "bad syntax" end
m, p = S.load(env)
eq(#p, 1, "corrupt: one problem")
problemsMention(p, "bad syntax", "corrupt: message kept")
eq(m.theme, "perdow", "corrupt: defaults")
env.load = function() return nil end
m, p = S.load(env)
eq(#p, 1, "load returns nil without message: one problem")
env.load = function() return "text" end
m, p = S.load(env)
eq(#p, 1, "non-table load: one problem")
eq(m.theme, "perdow", "non-table load: defaults")

-- partial and bad content in file
env = fakeEnv()
env.files[FILE] = { theme = "sosel", bogus = 1 }
m, p = S.load(env)
eq(m.theme, "sosel", "partial file merged")
eq(#p, 1, "partial file: unknown key reported")

-- raising env functions
env = fakeEnv()
env.exists = function() error("boom") end
m, p = S.load(env)
eq(#p, 1, "exists raises: one problem")
eq(m.theme, "perdow", "exists raises: defaults")
env = fakeEnv()
env.files[FILE] = true
env.load = function() error("boom") end
m, p = S.load(env)
eq(#p, 1, "load raises: one problem")
problemsMention(p, "boom", "load raises: message kept")
env = fakeEnv()
env.save = function() error("disk full") end
local ok, err = S.save(env, S.defaults())
eq(ok, nil, "save raises: nil")
eq(tostring(err):find("disk full", 1, true) ~= nil, true, "save raises: message kept")

-- bad env
m, p = S.load(nil)
eq(#p, 1, "load nil env: one problem")
eq(m.theme, "perdow", "load nil env: defaults")
m, p = S.load({})
eq(#p, 1, "load env without homeDir: one problem")
ok, err = S.save(nil, S.defaults())
eq(ok, nil, "save nil env")
eq(type(err), "string", "save nil env: message")
ok, err = S.save({ homeDir = 5 }, S.defaults())
eq(ok, nil, "save bad homeDir")

-- save failures reported by env
env = fakeEnv()
env.save = function() return nil, "read-only" end
ok, err = S.save(env, S.defaults())
eq(ok, nil, "save failure: nil")
eq(err, "read-only", "save failure: message")
env.save = function() return false end
ok, err = S.save(env, S.defaults())
eq(err, "save failed", "save failure without message")

-- save of an invalid table writes only clean data
env = fakeEnv()
ok, err = S.save(env, "junk")
eq(ok, nil, "save non-table: nil")
eq(env.files[FILE], nil, "save non-table: nothing written")
local junk = { theme = 5, evil = "x", layout = { mode = "huge", extra = 1 }, chat = { maxLines = 5, keepInMain = { tells = "no", mirel = true } } }
eq(S.save(env, junk), true, "save invalid table still succeeds with clean data")
local w = env.files[FILE]
eq(w.theme, "perdow", "junk: theme replaced")
eq(w.evil, nil, "junk: unknown key dropped")
eq(w.layout.extra, nil, "junk: unknown layout key dropped")
eq(w.layout.mode, "auto", "junk: mode replaced")
eq(w.chat.maxLines, 2000, "junk: maxLines replaced")
eq(w.chat.keepInMain.mirel, nil, "junk: unknown keepInMain dropped")
eq(w.chat.keepInMain.tells, true, "junk: keepInMain replaced")
eq(junk.theme, 5, "junk input not mutated")

---------------------------------------------------------------- review regressions
eq(select("#", S.path("a\\b")), 1, "path returns one value")
eq(math.type(S.merge({ chat = { maxLines = 500.0 } }).chat.maxLines), "integer", "maxLines float normalised")
local hostile = setmetatable({}, { __index = function() error("boom") end })
local hm, hp = S.merge(hostile)
eq(hm.theme, "perdow", "hostile table: defaults")
eq(#hp, 1, "hostile table: one problem")
eq(select("#", S.save({ homeDir = "x", save = function() return true end }, hostile)), 1, "hostile save returns")

if COVER then
    debug.sethook()
    local path = root .. "/src/scripts/core/settings.lua"
    local n = 0
    for l in io.lines(path) do
        n = n + 1
        local code = l:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$") or code:match("^local function")
            or code:match("^function ") or code:match("^[%]})]+,?$") or code:match("^elseif") or code:match("^}$")
        if not skip and not hit[path .. ":" .. n] and not hit[("%s:%d"):format(path, n)] then
            print(("not run  settings.lua:%d  %s"):format(n, code))
        end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
