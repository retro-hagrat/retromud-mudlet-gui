-- Tests for src/scripts/transport/routes.lua. Run from the repo root: lua test/transport_test.lua
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
dofile(root .. "/src/scripts/transport/routes.lua")
local T = rmgui.transport
local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

eq(table.concat(T.expand("n;4 ne;2 n"), " "), "n ne ne ne ne n n", "shaft 0 expands")
eq(table.concat(T.expand("9ne, d ,#2 s"), " "), "ne ne ne ne ne ne ne ne ne d s s", "glued counts, spaces and # counts")
eq(#T.expand("38e"), 38, "38e")
eq(select(2, T.expand("n;??")) ~= nil, true, "junk step rejected")
eq(T.expand("500n"), nil, "runaway count rejected")

for kind, g in pairs(T.groups) do
    for name, path in pairs(g.routes) do
        eq(T.expand(path) ~= nil, true, "route parses: " .. kind .. " " .. name)
    end
end

local sent, said = {}, {}
local function send(c) sent[#sent + 1] = c end
local levels = {}
local function out(m, l) said[#said + 1] = m; levels[#levels + 1] = l end
eq(T.go("ship", "WSH", send, out), true, "known route")
eq(table.concat(sent, " "), "nw w w w w w w w w", "sent one command per step")
eq(levels[1], "ok", "success is reported green")
sent = {}
eq(T.go("ship", "nope", send, out), false, "unknown name")
eq(levels[2], "err", "refusal is reported red")
eq(T.go("nope", "x", send, out), false, "unknown kind")
eq(#sent, 0, "nothing sent on a bad request")
eq(#T.help(), 7, "help lists every group")

print(("transport: %d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
