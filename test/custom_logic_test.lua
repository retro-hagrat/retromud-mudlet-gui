-- Tests for src/scripts/custom/logic.lua. Run from the repo root: lua test/custom_logic_test.lua
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
dofile(root .. "/src/scripts/custom/logic.lua")
local C = rmgui.custom
local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then fails = fails + 1 print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want))) end
end

eq(C.COUNT, 12, "twelve buttons"); eq(C.COLS, 4, "four columns")
eq(C.clean("  heal  ", 12), "heal", "trimmed")
eq(C.clean("a\nb\tc\r", 12), "a b c", "control characters become spaces")
eq(C.clean("abcdefghijklmnop", 5), "abcde", "cut to max")
eq(C.clean("   ", 5), nil, "blank is nothing"); eq(C.clean(5, 5), nil, "not a string"); eq(C.clean(nil, 5), nil, "nil")

local slots, dropped = C.decode({
    { slot = 1, label = "heal", command = "cast heal" },
    { slot = 12, label = "x", command = "look" },
    { slot = 13, label = "x", command = "look" },      -- out of range
    { slot = 0, label = "x", command = "look" },
    { slot = 1.5, label = "x", command = "look" },
    { slot = 2, label = "x" },                           -- no command
    { slot = 3, command = "look" },                      -- no label
    { slot = 1, label = "dup", command = "dup" },        -- slot taken
    "junk", 7, { slot = "4", label = "x", command = "y" },
})
eq(slots[1].command, "cast heal", "slot 1 kept"); eq(slots[12].label, "x", "slot 12 kept")
eq(slots[1].label, "heal", "the first entry for a slot wins")
eq(slots[2], nil, "no command: dropped"); eq(slots[3], nil, "no label: dropped"); eq(slots[13], nil, "out of range")
eq(dropped, 9, "dropped entries are counted")
local none, d0 = C.decode(nil); eq(next(none), nil, "nil list"); eq(d0, 0, "nothing dropped for nil")
eq(next((C.decode("junk"))), nil, "string list")

local list = C.encode({ [5] = { label = "b", command = "c" }, [2] = { label = "a", command = "d" } })
eq(#list, 2, "encode count"); eq(list[1].slot, 2, "encode in slot order"); eq(list[2].slot, 5, "encode second")
eq(C.encode({})[1], nil, "encode empty")
local again = C.decode(C.encode(slots)); eq(again[12].command, "look", "round trip")

local s = {}
eq(C.set(s, 3, "heal", "cast heal"), true, "set"); eq(s[3].command, "cast heal", "set stored")
eq(C.set(s, 4, "", "look"), true, "no name is fine"); eq(s[4].label, "look", "name taken from the command")
eq(select(2, C.set(s, 5, "x", "")), "the command is empty", "name without command")
eq(s[5], nil, "not stored")
eq(C.set(s, 3, "", ""), true, "both empty clears"); eq(s[3], nil, "cleared")
eq(select(2, C.set(s, 13, "a", "b")), "no such button", "out of range"); eq(C.set(s, 0, "a", "b"), false, "zero")
eq(C.set(s, "1", "a", "b"), false, "string slot"); eq(C.set(s, 1.5, "a", "b"), false, "fraction slot")
C.set(s, 6, "n", ("x"):rep(500)); eq(#s[6].command, 200, "command cut to 200")
print(("custom_logic: %d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
