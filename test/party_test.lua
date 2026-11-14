-- Tests for src/scripts/party (parser and glue). Run from the repo root: lua test/party_test.lua
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local F = dofile(root .. "/test/fake_mudlet.lua")
F.reset()
for _, f in ipairs({ "core/lifecycle", "core/env", "theme/presets", "theme/logic", "theme/apply", "party/parser", "party/glue" }) do
    dofile(root .. "/src/scripts/" .. f .. ".lua")
end
local P = rmgui.party

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

local RULE = "====================================================================="
local A = "|Hagrat       | HP:  3127/3127  | SP:   988/988   | EP:  2070/2070  |"
local B = "|Hagrattest   | HP:   296/296   | SP:   102/102   | EP:    74/74    |"

-- parser
local r = P.parseRow(A)
eq(r.name, "Hagrat", "name trimmed"); eq(r.hp, 3127, "hp"); eq(r.hpMax, 3127, "hpMax")
eq(r.sp, 988, "sp"); eq(r.ep, 2070, "ep"); eq(r.epMax, 2070, "epMax")
eq(P.parseRow(B).ep, 74, "padded ep")
eq(P.parseRow("|Bob | HP: -5/100 | SP: 1/1 | EP: 1/1 |").hp, -5, "negative hp")
eq(P.parseRow("|Bob | HP: 5/0 | SP: 1/1 | EP: 1/1 |"), nil, "zero max rejected")
eq(P.parseRow("|Bob | HP: x/9 | SP: 1/1 | EP: 1/1 |"), nil, "junk rejected")
eq(P.parseRow("Hp: 1/1 Sp: 1/1 Ep: 1/1 >"), nil, "prompt is not a row")
eq(P.parseRow(nil), nil, "nil")
eq(P.isRule(RULE), true, "rule"); eq(P.isRule("=== x"), false, "not a rule")

local st = {}
eq(P.feed(st, "pssa"), nil, "command echo ignored")
eq(P.feed(st, RULE), nil, "open")
eq(P.feed(st, A), nil, "row 1"); eq(P.feed(st, B), nil, "row 2")
local done = P.feed(st, RULE)
eq(#done, 2, "block closes with two members"); eq(done[2].name, "Hagrattest", "order kept")
eq(P.feed(st, A), nil, "row outside a block ignored")
P.feed(st, RULE); P.feed(st, A); eq(P.feed(st, "You hit a rat."), nil, "interrupt drops the block")
eq(st.rows, nil, "state reset")
P.feed(st, RULE); eq(#P.feed(st, RULE), 0, "empty block")
P.feed(st, RULE); for _ = 1, 9 do P.feed(st, A) end
eq(st.rows, nil, "more than 8 rows drops the block")

-- glue
local env = rmgui.core.makeEnv()
local slot = Geyser.Container:new({ name = "test.slot", x = 0, y = 0, width = 200, height = 200 })
rmgui.layout = { get = function(n) if n == "party" then return slot end end }
P.init(env)
local function w(i, k) return F.objects["rmgui.party." .. i .. "." .. k] end
eq(w(8, "ep") ~= nil and w(9, "ep") == nil, true, "eight rows of bars")
eq(w(1, "name").hidden, true, "unused rows hidden")
F.lines(RULE, A, B, RULE)
eq(w(1, "name").text, "Hagrat", "row 1 name"); eq(w(1, "name").hidden, false, "row 1 shown")
eq(w(2, "hp").text.text, "296/296", "numbers on the bar"); eq(w(2, "hp").text.textColor, "black", "black text")
eq(w(2, "hp").value, 296, "row 2 hp"); eq(w(2, "sp").max, 102, "row 2 sp max")
eq(w(3, "hp").hidden, true, "row 3 still hidden")
F.lines(RULE, B, RULE)
eq(w(1, "name").text, "Hagrattest", "second block replaces the first")
eq(w(2, "hp").hidden, true, "member who left is hidden")
rmgui.theme.apply("welstar", env, {})
eq(w(1, "hp").styleFront ~= nil, true, "themed")
P.teardown(env)
eq(w(1, "hp"), nil, "gauges gone"); eq(#F.triggers, 0, "trigger gone")
print(("party: %d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
