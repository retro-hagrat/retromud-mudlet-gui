-- Tests for src/scripts/vitals/parser.lua. Run from the repo root: lua test/vitals_parser_test.lua
-- COVER=1 prints the lines of parser.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local before = {}
for k in pairs(_G) do before[k] = true end
dofile(root .. "/src/scripts/vitals/parser.lua")
local V = rmgui.vitals

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function fields(line, want, label)
    local r = V.parse(line)
    eq(type(r), "table", label .. " parses")
    if r then
        for _, k in ipairs({ "hp", "hpMax", "sp", "spMax", "ep", "epMax", "gold", "exp" }) do
            eq(r[k], want[k], label .. " " .. k)
        end
    end
end
local function no(line, label) eq(V.parse(line), nil, "nil: " .. label) end

---------------------------------------------------------------- globals
local extra = {}
for k in pairs(_G) do if not before[k] and k ~= "rmgui" then extra[#extra + 1] = k end end
eq(#extra, 0, "no global besides rmgui")

---------------------------------------------------------------- isPromptLine
eq(V.isPromptLine("Hp: 1/2"), true, "prompt line")
eq(V.isPromptLine("Hp:"), true, "prompt line bare")
eq(V.isPromptLine(" Hp: 1/2"), false, "leading space")
eq(V.isPromptLine("hp: 1/2"), false, "case")
eq(V.isPromptLine("Aldric: Hp:"), false, "not col 1")
eq(V.isPromptLine(nil), false, "nil")
eq(V.isPromptLine(5), false, "number")
eq(V.isPromptLine(""), false, "empty")

---------------------------------------------------------------- shapes
local base = { hp = 10, hpMax = 20, sp = 5, spMax = 9, ep = 7, epMax = 7 }
local function with(t, extra2) local r = {} for k, v in pairs(t) do r[k] = v end for k, v in pairs(extra2) do r[k] = v end return r end
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: 3 Exp: 40 >", with(base, { gold = 3, exp = 40 }), "full")
fields("Hp:10/20 Sp:5/9 Ep:7/7 Exp:40 >", with(base, { exp = 40 }), "tight exp")
fields("Hp: 10/20 Sp: -5/9 Ep: 7/7 >", with(base, { sp = -5 }), "negative")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 >", base, "plain")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: 3 >", with(base, { gold = 3 }), "gold only")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold:3 Exp:40 >", with(base, { gold = 3, exp = 40 }), "gold tight")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: -3 >", with(base, { gold = -3 }), "negative gold")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 Exp:40 >fighter say hi", with(base, { exp = 40 }), "glued command")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 > ", base, "trailing space")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 >\r", base, "carriage return")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 >  \r", base, "spaces and cr")
fields("Hp: 10/20   Sp: 5/9  Ep: 7/7    >", base, "many spaces between")
fields("Hp: 0/1 Sp: 0/1 Ep: 0/1 >", { hp = 0, hpMax = 1, sp = 0, spMax = 1, ep = 0, epMax = 1 }, "zero and one")
local B = 1000000000
fields(("Hp: %d/%d Sp: -%d/%d Ep: 1/1 Gold: %d Exp: -%d >"):format(B, B, B, B, B, B),
    { hp = B, hpMax = B, sp = -B, spMax = B, ep = 1, epMax = 1, gold = B, exp = -B }, "upper bound")

---------------------------------------------------------------- rejections
no("Aldric [retro]: Hp: 10/20 Sp: 5/9 Ep: 7/7 >", "chat prefix")
no("Aldric says 'Hp: 1/2 Sp: 1/2 Ep: 1/2 >'", "say")
no(" Hp: 10/20 Sp: 5/9 Ep: 7/7 >", "leading space")
no("hp: 10/20 Sp: 5/9 Ep: 7/7 >", "lowercase hp")
no("Hp: 10/20 sp: 5/9 Ep: 7/7 >", "lowercase sp")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 gold: 3 >", "lowercase gold")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 EXP: 3 >", "uppercase exp")
no("Hp: 10/20 Sp: 5/9 >", "missing ep")
no("Hp: 10/20 Ep: 7/7 >", "missing sp")
no("Hp: 10/20 >", "only hp")
no("Hp: 10 Sp: 5/9 Ep: 7/7 >", "no max")
no("Hp: 10/ Sp: 5/9 Ep: 7/7 >", "empty max")
no("Hp: /20 Sp: 5/9 Ep: 7/7 >", "empty cur")
no("Hp: 10/-20 Sp: 5/9 Ep: 7/7 >", "negative max")
no("Hp: 10/0 Sp: 5/9 Ep: 7/7 >", "hp max zero")
no("Hp: 10/20 Sp: 5/0 Ep: 7/7 >", "sp max zero")
no("Hp: 10/20 Sp: 5/9 Ep: 7/0 >", "ep max zero")
no("Hp: 1,000/2,000 Sp: 5/9 Ep: 7/7 >", "separators")
no("Hp: 1.5/20 Sp: 5/9 Ep: 7/7 >", "decimal")
no("Hp:  10/20 Sp: 5/9 Ep: 7/7 >", "two spaces after colon")
no("Hp: 10/20Sp: 5/9 Ep: 7/7 >", "no space between hp and sp")
no("Hp: 10/20 Sp: 5/9Ep: 7/7 >", "no space between sp and ep")
no("Hp: 10/20 Ep: 7/7 Sp: 5/9 >", "wrong order")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7", base, "short tick prompt")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 ", base, "short tick prompt, trailing space")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 Exp: 4", "no closing, exp")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: 3 Gold: 4 >", "gold twice")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 Exp: 3 Exp: 4 >", "exp twice")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 Exp: 3 Gold: 4 >", with(base, { gold = 4, exp = 3 }), "exp before gold")
fields("Hp: 10/20  Sp: 5/9  Ep: 7/7", base, "short tick prompt, two spaces")
fields("Hp:2698/2698 Sp:1793/1793 Ep:1079/1079 Xp:0 Money:14365 >",
    { hp = 2698, hpMax = 2698, sp = 1793, spMax = 1793, ep = 1079, epMax = 1079, gold = 14365, exp = 0 }, "Xp and Money, tight")
no("Hp:2698/2698 Sp:1793/1793 Ep:1079/1079 Xp:0 Money:14365", "fields with no closing >")
fields("Hp: 10/20 Sp: 5/9 Ep: 7/7 Xp: 40 Money: 3 >", with(base, { gold = 3, exp = 40 }), "Xp and Money")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7x", "junk right after Ep")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 Money: 3 Gold: 4 >", "gold twice under two names")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 xp: 3 >", "lowercase xp")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 Mana: 3 >", "unknown field")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: >", "gold no value")
no("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: 3Exp: 4 >", "no space before exp")
no("", "empty")
no(nil, "nil")
no(42, "number")
no({}, "table")
no(true, "boolean")

---------------------------------------------------------------- boundaries
local function line(cur, max, gold)
    return ("Hp: %s/%s Sp: 1/1 Ep: 1/1%s >"):format(cur, max, gold and (" Gold: " .. gold) or "")
end
eq(V.parse(line(0, 1)).hp, 0, "cur 0")
eq(V.parse(line(1, 1)).hp, 1, "cur 1")
eq(V.parse(line(B, B)).hpMax, B, "max 1e9")
no(line(B + 1, B), "cur 1e9+1")
no(line(1, B + 1), "max 1e9+1")
no(line(-B - 1, 5), "cur -1e9-1")
eq(V.parse(line(-B, 5)).hp, -B, "cur -1e9")
no(line(1, 0), "max 0")
no(line(1, 1, B + 1), "gold 1e9+1")
eq(V.parse(line(1, 1, B)).gold, B, "gold 1e9")
no(line(1, 1, -B - 1), "gold -1e9-1")
no(line(("9"):rep(400), 5), "huge digits")
no(("Hp: 1/1 Sp: 1/1 Ep: 1/1 Exp: %s >"):format(B + 1), "exp 1e9+1")

---------------------------------------------------------------- input not mutated
local s = "Hp: 10/20 Sp: 5/9 Ep: 7/7 >"
V.parse(s)
eq(s, "Hp: 10/20 Sp: 5/9 Ep: 7/7 >", "string unchanged")

---------------------------------------------------------------- changed
local a = V.parse("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: 3 Exp: 40 >")
local b = V.parse("Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: 3 Exp: 40 >")
eq(V.changed(a, b), false, "equal tables")
eq(V.changed(nil, b), true, "old nil")
eq(V.changed(a, nil), false, "new nil")
eq(V.changed(nil, nil), false, "both nil")
eq(V.changed("x", b), true, "old not a table")
eq(V.changed(a, "x"), false, "new not a table")
for _, k in ipairs({ "hp", "hpMax", "sp", "spMax", "ep", "epMax", "gold", "exp" }) do
    local c = {}
    for kk, v in pairs(b) do c[kk] = v end
    c[k] = c[k] + 1
    eq(V.changed(a, c), true, "differs in " .. k)
    c[k] = nil
    eq(V.changed(a, c), true, "field removed " .. k)
end
eq(V.changed(V.parse("Hp: 1/2 Sp: 1/2 Ep: 1/2 >"), a), true, "gold appears")

---------------------------------------------------------------- percent
eq(V.percent(10, 20), 50, "half")
eq(V.percent(0, 20), 0, "zero")
eq(V.percent(5, 0/0), 0, "NaN max is 0")
eq(V.percent(math.huge, math.huge), 0, "inf/inf is 0")
eq(V.percent(20, 20), 100, "full")
eq(V.percent(30, 20), 100, "over clamps")
eq(V.percent(-5, 20), 0, "negative cur")
eq(V.percent(1, 3), 33, "floors")
eq(V.percent(2, 3), 66, "floors 2/3")
eq(V.percent(1, 0), 0, "max zero")
eq(V.percent(1, -4), 0, "max negative")
eq(V.percent(nil, 5), 0, "cur nil")
eq(V.percent(5, nil), 0, "max nil")
eq(V.percent("5", 10), 0, "cur string")
eq(V.percent(5, "10"), 0, "max string")
eq(V.percent(0 / 0, 10), 0, "nan")
eq(math.type(V.percent(1, 3)), "integer", "integer result")

---------------------------------------------------------------- speed
local samples = {
    "Hp: 10/20 Sp: 5/9 Ep: 7/7 Gold: 3 Exp: 40 >", "Hp:10/20 Sp:5/9 Ep:7/7 Exp:40 >",
    "Aldric [retro]: Hp: 10/20 Sp: 5/9 Ep: 7/7 >", "Mirel says 'a quiet night in the hall'",
    "Hp: 10/20 Sp: 5/9 Ep: 7/7 >fighter say hi", "Hp: 10/20 Sp: 5/9", "Bran enters the room.", "",
}
local t0 = os.clock()
for i = 1, 100000 do V.parse(samples[i % #samples + 1]) end
local per = (os.clock() - t0) * 1000 / 100000
eq(per < 1, true, ("speed %.5f ms per line"):format(per))

---------------------------------------------------------------- coverage
if COVER then
    debug.sethook()
    local path = root .. "/src/scripts/vitals/parser.lua"
    local n = 0
    for l in io.lines(path) do
        n = n + 1
        local code = l:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$") or code:match("^local function")
            or code:match("^function ") or code:match("^[%]})]+,?$") or code:match("^elseif") or code:match("^}$") or code:match("^while true do")
        if not skip and not hit[path .. ":" .. n] and not hit[("%s:%d"):format(path, n)] then
            print(("not run  parser.lua:%d  %s"):format(n, code))
        end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
