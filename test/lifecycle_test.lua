-- Tests for src/scripts/core/lifecycle.lua. Run from the repo root: lua test/lifecycle_test.lua
-- COVER=1 prints the lines of lifecycle.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local path = root .. "/src/scripts/core/lifecycle.lua"
dofile(path)
local C = rmgui.core

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function seq(t) return table.concat(t, ",") end

local log
local function rec(name, fail)
    return {
        init = function() log[#log + 1] = "init:" .. name; if fail == "init" then error("boom " .. name) end end,
        teardown = function() log[#log + 1] = "down:" .. name; if fail == "down" then error("bang " .. name) end end,
    }
end

-- fake env with event registry
local function fakeEnv(opts)
    opts = opts or {}
    local env = { handlers = {}, killed = {}, said = {}, nextId = 0, cleared = {} }
    function env.registerEvent(ev, fn)
        env.nextId = env.nextId + 1
        env.handlers[env.nextId] = { ev = ev, fn = fn }
        return env.nextId
    end
    function env.killEvent(id) env.killed[#env.killed + 1] = id; env.handlers[id] = nil end
    if not opts.noSay then function env.say(m, kind) env.said[#env.said + 1] = kind .. ":" .. m end end
    if not opts.noClear then function env.clearGlobal(n) env.cleared[#env.cleared + 1] = n end end
    function env.live()
        local n = 0
        for _ in pairs(env.handlers) do n = n + 1 end
        return n
    end
    function env.fire(ev, ...)
        local ids = {}
        for id, h in pairs(env.handlers) do if h.ev == ev then ids[#ids + 1] = id end end
        table.sort(ids)
        for _, id in ipairs(ids) do env.handlers[id].fn(ev, ...) end
    end
    return env
end

---------------------------------------------------------------- register
log = {}
eq(C.register("a", rec("a")), true, "register ok")
eq(C.register("b", rec("b", "init")), true, "register failing init")
eq(C.register("c", rec("c", "down")), true, "register failing teardown")
eq(C.register("d", { }), true, "register empty module")
eq(C.register("e", { init = 5, teardown = "x" }), true, "non-function hooks accepted")
eq(C.register("", {}), false, "empty name rejected")
eq(C.register(nil, {}), false, "nil name rejected")
eq(C.register(7, {}), false, "number name rejected")
eq(C.register("z", nil), false, "nil mod rejected")
eq(C.register("z", "str"), false, "string mod rejected")
eq(seq(C.state().order), "a,b,c,d,e", "order after register")
eq(C.state().started, false, "not started initially")

---------------------------------------------------------------- start / stop
local env = fakeEnv()
eq(C.start(env), true, "start returns true")
eq(seq(log), "init:a,init:b,init:c", "init order, failing module still attempted")
eq(env.said[1]:find("^err:") ~= nil and env.said[1]:find("boom b", 1, true) ~= nil, true, "failure reported with err kind")
eq(#env.said, 1, "only one report")
eq(seq(C.state().failed), "b", "failed recorded")
eq(C.state().started, true, "started")
local n = #log
eq(C.start(env), false, "second start returns false")
eq(#log, n, "second start runs nothing")

log = {}
eq(C.stop(env), true, "stop returns true")
eq(seq(log), "down:c,down:a", "reverse teardown, failed init skipped")
eq(#env.said, 2, "teardown failure reported")
eq(env.said[2]:find("bang c", 1, true) ~= nil, true, "teardown error text")
eq(C.state().started, false, "stopped")
eq(seq(C.state().failed), "", "failed cleared on stop")
eq(C.stop(env), false, "stop when not started")

log = {}
eq(C.start(env), true, "restart after stop")
eq(seq(log), "init:a,init:b,init:c", "restart runs init again")
C.stop(env)

-- env without say, nil env, non-table env
log = {}
eq(pcall(C.start, fakeEnv({ noSay = true })), true, "start without say does not raise")
eq(C.stop(nil), true, "stop with nil env")
eq(C.start(nil), true, "start with nil env")
C.stop("junk")
eq(C.start("junk"), true, "start with string env")
C.stop()
-- say that raises is contained
local rs = { say = function() error("say broke") end }
eq(C.start(rs), true, "raising say contained")
eq(C.stop(rs), true, "raising say contained on stop")

---------------------------------------------------------------- re-register keeps position
log = {}
C.register("a", rec("a2"))
eq(seq(C.state().order), "a,b,c,d,e", "re-register keeps position")
C.start(fakeEnv())
eq(log[1], "init:a2", "re-register replaces module")
C.stop(fakeEnv())

---------------------------------------------------------------- state copies
local s = C.state()
s.order[1] = "hacked"; s.order[#s.order + 1] = "extra"; s.failed[1] = "hacked"; s.started = true
local s2 = C.state()
eq(s2.order[1], "a", "order copy cannot corrupt")
eq(#s2.order, 5, "order length intact")
eq(s2.started, false, "started copy cannot corrupt")
C.start(fakeEnv())
local f = C.state()
f.failed[1] = "hacked"; f.failed[2] = "more"
eq(seq(C.state().failed), "b", "failed copy cannot corrupt")
C.stop(fakeEnv())

---------------------------------------------------------------- install guards
eq(C.install({}, "pkg"), false, "install needs registerEvent")
eq(C.install({ registerEvent = function() end }, "pkg"), false, "install needs killEvent")
eq(C.install(nil, "pkg"), false, "install nil env")
eq(C.uninstall({}), false, "uninstall needs killEvent")
eq(C.uninstall(nil), false, "uninstall nil env")

---------------------------------------------------------------- events
local e1 = fakeEnv()
log = {}
eq(C.install(e1, "retromud-gui"), true, "install ok")
eq(e1.live(), 3, "three handlers")
local evs = {}
for _, h in pairs(e1.handlers) do evs[#evs + 1] = h.ev end
table.sort(evs)
eq(seq(evs), "sysInstallPackage,sysLoadEvent,sysUninstallPackage", "event names")

e1.fire("sysLoadEvent")
eq(C.state().started, true, "load event starts")
n = #log
e1.fire("sysLoadEvent")
eq(#log, n, "load event ignored when started")
C.stop(e1)

e1.fire("sysInstallPackage", "other")
eq(C.state().started, false, "install event wrong package ignored")
e1.fire("sysInstallPackage")
eq(C.state().started, false, "install event without package ignored")
e1.fire("sysInstallPackage", "retromud-gui")
eq(C.state().started, true, "install event right package starts")

log = {}
e1.fire("sysUninstallPackage", "other")
eq(C.state().started, true, "uninstall wrong package ignored")
eq(e1.live(), 3, "handlers kept on wrong package")
eq(#e1.cleared, 0, "global kept on wrong package")
e1.fire("sysUninstallPackage", "retromud-gui")
eq(C.state().started, false, "uninstall stops")
eq(log[1], "down:c", "uninstall ran teardown")
eq(e1.live(), 0, "uninstall kills handlers")
eq(seq(e1.cleared), "rmgui", "uninstall clears global")

-- no clearGlobal, not started
local e2 = fakeEnv({ noClear = true })
C.install(e2, "p")
e2.fire("sysUninstallPackage", "p")
eq(e2.live(), 0, "uninstall without clearGlobal and not started")

-- registerEvent that raises is contained
local e3 = fakeEnv()
local reg = e3.registerEvent
e3.registerEvent = function(ev, fn) if ev == "sysLoadEvent" then error("no") end return reg(ev, fn) end
eq(C.install(e3, "p"), true, "raising registerEvent contained")
eq(e3.live(), 2, "other handlers still registered")
C.uninstall(e3)

---------------------------------------------------------------- no leaks
local e4 = fakeEnv()
for _ = 1, 5 do
    C.install(e4, "p")
    eq(e4.live(), 3, "no leak while installed")
    C.uninstall(e4)
    eq(e4.live(), 0, "no leak after uninstall")
end
C.install(e4, "p"); C.install(e4, "p"); C.install(e4, "p")
eq(e4.live(), 3, "double install keeps one set")
eq(C.uninstall(e4), true, "uninstall ok")
eq(e4.live(), 0, "all gone")
eq(C.uninstall(e4), true, "uninstall twice is fine")

---------------------------------------------------------------- review regressions
local e5 = fakeEnv()
eq(C.install(e5), false, "install without package name rejected")
eq(C.install(e5, ""), false, "install with empty package name rejected")
eq(e5.live(), 0, "no handlers after rejected install")

do
    local calls = 0
    C.register("rA", { teardown = function() calls = calls + 1 end })
    C.register("rB", { teardown = function(e) C.stop(e) end })
    C.start({})
    local ok = pcall(C.stop, {})
    eq(ok, true, "stop inside teardown does not raise")
    eq(calls, 1, "stop inside teardown does not run teardowns twice")
    eq(C.state().started, false, "stopped after re-entrant stop")
    local hostile = setmetatable({}, { __index = function() error("boom") end })
    eq(C.register("rH", hostile), true, "hostile mod registered")
    eq(pcall(C.start, {}), true, "start survives hostile mod")
    eq(pcall(C.stop, {}), true, "stop survives hostile mod")
end

if COVER then
    debug.sethook()
    local n2 = 0
    for l in io.lines(path) do
        n2 = n2 + 1
        local code = l:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$") or code:match("^local function")
            or code:match("^function ") or code:match("^[%]})]+,?$") or code:match("^elseif") or code:match("^}$")
        if not skip and not hit[path .. ":" .. n2] and not hit[("%s:%d"):format(path, n2)] then
            print(("not run  lifecycle.lua:%d  %s"):format(n2, code))
        end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
