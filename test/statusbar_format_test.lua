-- Tests for src/scripts/statusbar/format.lua. Run from the repo root: lua test/statusbar_format_test.lua
-- COVER=1 prints the lines of format.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
dofile(root .. "/src/scripts/statusbar/format.lua")
local F = rmgui.statusbar.format

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function run(s, o) return F(s, o) end
local function txt(s, o) return F(s, o).text end

local NIL = {} -- pairs() cannot carry nil, so this marks "unset"
local function base(t)
    local s = { roomName = "Mirel Hall", areaName = "Bran Keep", mapping = true, syncState = "SYNCED", mapperInstalled = true }
    for k, v in pairs(t or {}) do if v == NIL then s[k] = nil else s[k] = v end end
    return s
end

-- full matrix, no truncation
for _, mapperInstalled in ipairs({ true, false }) do
for _, mapping in ipairs({ true, false }) do
for _, sync in ipairs({ "SYNCED", "PENDING", "UNSYNCED", "none", false }) do
for _, hasArea in ipairs({ true, false }) do
    local s = base({ mapperInstalled = mapperInstalled, mapping = mapping, syncState = sync or NIL, areaName = hasArea and "Bran Keep" or NIL })
    if sync == "none" then s.syncState = nil end
    if sync == false then s.syncState = "bogus" end
    local want = { "Mirel Hall" }
    if not mapperInstalled then
        want[2] = "(mapper not installed)"
    elseif mapping and (sync == "SYNCED" or sync == "PENDING" or sync == "UNSYNCED") then
        if hasArea and sync ~= "UNSYNCED" then want[#want + 1] = "Bran Keep" end
        want[#want + 1] = "[" .. sync .. "]"
    end
    local r = run(s)
    local label = ("matrix inst=%s map=%s sync=%s area=%s"):format(tostring(mapperInstalled), tostring(mapping), tostring(sync), tostring(hasArea))
    eq(r.text, table.concat(want, "  "), label)
    eq(table.concat(r.parts, "|"), table.concat(want, "|"), label .. " parts")
    eq(r.text:find("   ", 1, true), nil, label .. " no triple space")
end end end end

-- spot checks of literal text
eq(txt(base()), "Mirel Hall  Bran Keep  [SYNCED]", "full text")
eq(txt(base({ syncState = "UNSYNCED" })), "Mirel Hall  [UNSYNCED]", "unsynced hides area")
eq(txt(base({ mapping = false })), "Mirel Hall", "mapping off")
eq(txt(base({ mapperInstalled = false })), "Mirel Hall  (mapper not installed)", "no mapper")
eq(txt(base({ areaName = "  " })), "Mirel Hall  [SYNCED]", "blank area leaves no gap")
eq(txt(base({ mapperInstalled = NIL, areaName = 5 })), "Mirel Hall  (mapper not installed)", "mapperInstalled nil")
eq(txt(base({ mapping = "yes" })), "Mirel Hall", "mapping must be boolean true")

-- room fallback
eq(txt(base({ roomName = NIL })), "no room yet  Bran Keep  [SYNCED]", "nil room")
eq(txt(base({ roomName = "" })), "no room yet  Bran Keep  [SYNCED]", "empty room")
eq(txt(base({ roomName = " \n\t " })), "no room yet  Bran Keep  [SYNCED]", "blank room")
eq(txt({ mapperInstalled = false }), "no room yet  (mapper not installed)", "fallback without mapper")

-- cleaning
eq(txt(base({ roomName = "Mirel\nHall\r\n" })), "Mirel Hall  Bran Keep  [SYNCED]", "newline and CR")
eq(txt(base({ roomName = "A\t\tB   C" })), "A B C  Bran Keep  [SYNCED]", "tab and runs collapse")
eq(txt(base({ areaName = "\tBran  \n Keep " })), "Mirel Hall  Bran Keep  [SYNCED]", "area cleaned")

-- non-string and bad inputs
for _, bad in ipairs({ 5, true, {}, print }) do
    eq(txt(base({ roomName = bad, areaName = bad })), "no room yet  [SYNCED]", "non-string names " .. type(bad))
end
eq(txt(nil), "no room yet  (mapper not installed)", "state nil")
eq(txt("x"), "no room yet  (mapper not installed)", "state string")
eq(txt(base(), "x"), "Mirel Hall  Bran Keep  [SYNCED]", "opts not a table")
eq(#run(nil, nil).parts, 2, "parts for nil state")

-- input not mutated
local s0 = base({ roomName = "A\nB" })
run(s0, { maxChars = 3 })
eq(s0.roomName, "A\nB", "input untouched")

-- truncation steps; full text is 31 chars
local full = "Mirel Hall  Bran Keep  [SYNCED]"
eq(#full, 31, "full length")
eq(txt(base(), { maxChars = 31 }), full, "max equals length")
eq(txt(base(), { maxChars = 100 }), full, "max above length")
eq(txt(base(), { maxChars = 30 }), "Mirel Hall  Bran Keep", "one short drops state")
eq(txt(base(), { maxChars = 21 }), "Mirel Hall  Bran Keep", "area fits exactly")
eq(txt(base(), { maxChars = 20 }), "Mirel Hall", "area dropped")
eq(txt(base(), { maxChars = 10 }), "Mirel Hall", "room fits exactly")
eq(txt(base(), { maxChars = 9 }), "Mirel ...", "room truncated")
eq(txt(base(), { maxChars = 4 }), "M...", "max 4")
eq(txt(base(), { maxChars = 3 }), "Mir", "max 3 no dots")
eq(txt(base(), { maxChars = 1 }), "M", "max 1")
eq(txt(base({ syncState = "UNSYNCED" }), { maxChars = 14 }), "Mirel Hall", "unsynced state dropped first")
local r = run(base(), { maxChars = 20 })
eq(#r.parts, 1, "parts follow truncation")
eq(r.parts[1], r.text, "parts match text")
r = run(base(), { maxChars = 30 })
eq(table.concat(r.parts, "  "), r.text, "parts join to text")
eq(txt(base({ mapperInstalled = false }), { maxChars = 12 }), "Mirel Hall", "notice dropped")
eq(txt(base({ mapperInstalled = false }), { maxChars = 40 }), "Mirel Hall  (mapper not installed)", "notice kept")
eq(txt(base({ mapperInstalled = false }), { maxChars = 5 }), "Mi...", "notice then room")

-- invalid maxChars means no truncation
for _, m in ipairs({ 0, -3, 2.5, "5", true, {}, 0 / 0 }) do
    eq(txt(base(), { maxChars = m }), full, "invalid maxChars " .. tostring(m))
end
eq(txt(base(), { maxChars = 10.0 }), "Mirel Hall", "integral float ok")
eq(txt(base(), { maxChars = math.huge }), full, "huge max")

-- very long name
local long = ("Aldric"):rep(5000)
local lr = run(base({ roomName = long }), { maxChars = 40 })
eq(#lr.text, 40, "long name exact length")
eq(lr.text:sub(-3), "...", "long name dots")
eq(#run(base({ roomName = long })).text > 30000, true, "long name untruncated without max")

-- utf-8 stays valid
local u = run(base({ roomName = "Caf\195\169 Mirel" }), { maxChars = 7 })
eq(u.text, "Caf\195\169...", "utf8 cut on character")
eq(utf8.len(u.text), 7, "utf8 length")
local bad = run(base({ roomName = "Mirel\255Hall" }), { maxChars = 7 })
eq(bad.text, "Mire...", "invalid utf8 falls back to bytes")

if COVER then
    debug.sethook()
    local path = root .. "/src/scripts/statusbar/format.lua"
    local n = 0
    for l in io.lines(path) do
        n = n + 1
        local code = l:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$") or code:match("^local function")
            or code:match("^function ") or code:match("^elseif") or code:match("^}$")
        if not skip and not hit[path .. ":" .. n] and not hit[("%s:%d"):format(path, n)] then
            print(("not run  format.lua:%d  %s"):format(n, code))
        end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
