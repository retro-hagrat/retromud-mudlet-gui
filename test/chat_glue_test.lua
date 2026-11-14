-- Tests for src/scripts/chat/glue.lua against the fake Mudlet. Run from the repo root: lua test/chat_glue_test.lua
-- COVER=1 prints the lines of glue.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local F = dofile(root .. "/test/fake_mudlet.lua")
F.reset()
for _, f in ipairs({ "core/lifecycle", "core/env", "core/settings", "theme/presets", "theme/logic", "theme/apply",
                     "chat/rules", "chat/engine", "chat/router", "chat/glue" }) do
    dofile(root .. "/src/scripts/" .. f .. ".lua")
end
local G = rmgui.chat.glue

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function txt(id) return table.concat(F.consoleText("rmgui.chat.console." .. id), "|") end
local function tab(id) return F.objects["rmgui.chat.tab." .. id] end
local function tabText(id) return F.objects["rmgui.chat.tab." .. id .. ".text"] end -- the text label over the image

local slot, env, events
local function world(opts)
    opts = opts or {}
    F.reset()
    rmgui.theme.state = {}
    events = {}
    slot = Geyser.Container:new({ name = "slot", width = 400, height = 600 })
    rmgui.layout = { get = function(s) if not opts.noSlot and s == "chat" then return slot end end }
    env = rmgui.core.makeEnv()
    env.settings = rmgui.settings.defaults()
    env.saveSettings = function() end
    local raise = env.raise
    env.raise = function(ev, ...)
        if ev == "rmgui.onChat" then events[#events + 1] = { ... } end
        return raise(ev, ...)
    end
end
local function start(opts) world(opts); G.init(env) end

---------------------------------------------------------------- build
start()
eq(slot.children[1].name, "rmgui.chat.strip", "strip lives in the slot")
do -- the tab strip is 40 px high (the button height), whatever the slot height
    local strip = F.objects["rmgui.chat.strip"]
    eq(math.abs(strip:get_height() - 80) < 0.5, true, "tab strip is 80 px high (two rows) in a 600 px slot")
    eq(math.abs(F.objects["rmgui.chat.console.all"]:get_y() - slot:get_y() - 80) < 0.5, true, "console starts under the strip")
    slot.height = 300; F.fire("rmgui.onLayout", { layout = "wide" })
    eq(math.abs(strip:get_height() - 80) < 0.5, true, "strip stays 80 px after the slot shrinks to 300 px")
    eq(math.abs(F.objects["rmgui.chat.console.all"]:get_y() - slot:get_y() - 80) < 0.5, true, "console follows after a layout event")
    eq(math.abs(F.objects["rmgui.chat.console.all"]:get_height() - 220) < 0.5, true, "console height is the rest of the slot")
    slot.height = 600; F.fire("rmgui.onLayout", { layout = "wide" })
end
for _, id in ipairs({ "all", "chat", "world", "party", "info", "guild", "tells" }) do
    eq(tab(id) ~= nil, true, "tab " .. id)
    eq(F.objects["rmgui.chat.console." .. id] ~= nil, true, "console " .. id)
end
eq(tab("wizard"), nil, "wizard tab is lazy")
eq(tabText("all").text, "All", "title drawn")
eq(F.objects["rmgui.chat.console.all"].hidden, false, "all console shown")
eq(F.objects["rmgui.chat.console.chat"].hidden, true, "other console hidden")
eq(F.objects["rmgui.chat.console.all"].wrap == nil and F.objects["rmgui.chat.console.all"].autoWrap, true, "wrap on")
eq(F.objects["rmgui.chat.console.all"].maxLines, env.settings.chat.maxLines, "buffer limit set")
eq(#F.triggers, 1, "one trigger")
eq(tab("chat").x, "25.0000%", "tabs share the strip: four columns")
eq(tab("chat").y, "0.0000%", "second tab is in the first row")
eq(tab("guild").y, "50.0000%", "sixth tab is in the second row")
eq(tab("guild").x, "25.0000%", "sixth tab starts the second row at column two")

---------------------------------------------------------------- routing
F.lines("Aldric [mentor]: Welcome to the game!", "You [hit]: 120")
F.feedLine("Hp:1/1 >", { prompt = true })
eq(txt("all"), "Aldric [mentor]: Welcome to the game!", "all gets the line as the game sent it")
eq(txt("chat"), "Aldric [mentor]: Welcome to the game!", "chat tab")
eq(txt("world"), "", "world empty")
eq(F.lineDeleted, nil, "kept in main by default")
eq(#events, 1, "onChat raised once the message is complete")
local ev = events[1]
eq(ev[1] .. ev[2] .. ev[3] .. ev[4] .. ev[5], "mentorchatAldric[]Welcome to the game!", "onChat payload")

-- continuation: same tabs, no second prefix
world(); G.init(env)
F.lines("Aldric [mentor]: The trick with the first room is to look at", "      the sign twice.", "Nothing here.")
eq(txt("chat"), "Aldric [mentor]: The trick with the first room is to look at the sign twice.", "continuation joins the message with one space")
eq(events[1][5], "The trick with the first room is to look at the sign twice.", "wrapped text joined")

-- an indented rest joins the message, and the next message starts on a new line
world(); G.init(env)
F.lines("[info] Dalau the level 73 Mortal enters the game.", "      (16 players)", "Aldric [mentor]: hi", "Nothing here.")
eq(txt("info"), "[info] Dalau the level 73 Mortal enters the game. (16 players)", "(16 players) follows the message on its line")
eq(txt("all"), "[info] Dalau the level 73 Mortal enters the game. (16 players)|Aldric [mentor]: hi", "next message on a new line")


-- every form
local forms = {
    { "Aldric <chat>: waves hello", "chat" },
    { "Aldric < (=Fighter=) > one two three", "guild" },
    { "< ^abjurer^ > Aldric waves hello", "guild" },
    { "[welstar] A loud horn sounds", "world" },
    { "Aldric (Party): ready", "party" },
    { "[info] Aldric goes linkdead", "info" },
    { "[alert] Beware", "info" },
    { "Mirel telepathically contacts you with 'hello'", "tells" },
    { "Aldric < odd=thing > text", "guild" },
}
for _, f in ipairs(forms) do
    world(); G.init(env)
    F.lines(f[1], "plain text")
    local own = txt(f[2])
    eq(own:find(f[1], 1, true) ~= nil, true, "routed to " .. f[2] .. ": " .. f[1])
    eq(txt("all"):find(f[1], 1, true) ~= nil, true, "also on all: " .. f[1])
    eq(txt("all"):find("plain text", 1, true), nil, "plain text not copied")
end
world(); G.init(env)
F.lines("Mirel telepathically contacts you with 'hello'")
eq(txt("tells"), "Mirel telepathically contacts you with 'hello'", "tell has no prefix on its own tab")
eq(txt("all"), "Mirel telepathically contacts you with 'hello'", "tell has no prefix on all either")

-- history ignored
world(); G.init(env)
F.lines("Displaying last retro:", "[1700000200] [10:16:40] Aldric {retro}: one two three")
F.feedLine("Hp >", { prompt = true })
eq(txt("all"), "", "history not routed")
eq(#events, 0, "history raises nothing")

-- keepInMain false
world(); env.settings.chat.keepInMain.party = false; G.init(env)
F.lines("Aldric (Party): ready")
eq(F.lineDeleted, true, "keepInMain false deletes the line")
F.lineDeleted = nil
F.lines("Aldric [retro]: hi")
eq(F.lineDeleted, nil, "other groups stay")

---------------------------------------------------------------- wizard, unread
world(); G.init(env)
F.lines("Aldric <wiz>: test message", "x")
eq(txt("wizard"):find("Aldric <wiz>", 1, true) ~= nil, true, "wizard line arrives as the game sent it")
eq(tab("wizard") ~= nil, true, "wizard tab created")
eq(tab("chat").x, "25.0000%", "tabs re-spaced: eight tabs are still four columns")
F.lines("Aldric <arch>: again", "x")
local n = 0
for _, o in ipairs(F.objectList) do if o.name == "rmgui.chat.tab.wizard" then n = n + 1 end end
eq(n, 1, "wizard tab only once")

F.lines("Aldric [retro]: one", "Aldric [retro]: two")
eq(tabText("chat").text, "Chat 2", "unread count on chat")
eq(tabText("all").text, "All", "active tab has no count")
tab("chat"):fireClick()
eq(tabText("chat").text, "Chat", "count cleared on click")
eq(F.objects["rmgui.chat.console.chat"].hidden, false, "clicked console shown")
eq(F.objects["rmgui.chat.console.all"].hidden, true, "old console hidden")
F.lines("Aldric [retro]: three")
eq(tabText("all").text, "All 1", "all unread while another tab is active")
eq(tabText("chat").text, "Chat", "active chat stays clean")
tab("all"):fireClick()
eq(tabText("all").text, "All", "all cleared")

---------------------------------------------------------------- theme
world(); G.init(env)
local before = tab("chat").styleSheet
eq(before, nil, "no style before the theme")
rmgui.theme.apply("perdow", env, env.settings)
eq(type(tab("chat").styleSheet), "string", "tab styled")
eq(tab("all").styleSheet ~= tab("chat").styleSheet, true, "active tab styled differently")
eq(tabText("all").textColor:match("^#%x%x%x%x%x%x$") ~= nil, true, "hex text colour")
local s = rmgui.theme.presets.perdow.colors.surface
local c = F.objects["rmgui.chat.console.all"].color
eq(c[1] .. c[2] .. c[3], s[1] .. s[2] .. s[3], "console background from surface")
F.lines("Aldric [retro]: hi")
eq(tabText("chat").text, "Chat 1", "title redraw keeps unread")
rmgui.theme.apply("crypt", env, env.settings)
eq(tabText("chat").text, "Chat 1", "text survives a theme change")
local cs = rmgui.theme.presets.crypt.colors.surface
c = F.objects["rmgui.chat.console.all"].color
eq(c[1] .. c[2] .. c[3], cs[1] .. cs[2] .. cs[3], "console recoloured")
F.lines("Aldric <wiz>: w", "x")
eq(tab("wizard").styleSheet ~= nil, true, "lazy tab gets the current theme")

---------------------------------------------------------------- teardown and failure
local function empty(label)
    local k = F.counts()
    local own = slot.deleted and 0 or 1 -- the test's own slot container
    eq(k.objects - own + k.triggers + k.timers + k.handlers, 0, label)
    eq(#slot.children, 0, label .. " (slot children)")
end
world(); G.init(env); G.teardown(env)
empty("teardown leaves nothing")
eq(#rmgui.theme.list() > 0 and true, true, "theme list ok")
G.teardown(env); empty("teardown twice")
F.lines("Aldric [retro]: after")
eq(#events, 0, "no trigger after teardown")
G.init(env); G.init(env)
eq(F.counts().triggers, 1, "init after init gives no duplicate trigger")
eq(F.counts().handlers, 1, "one handler")
local objs = F.counts().objects
G.teardown(env); G.init(env)
eq(F.counts().objects, objs, "init after teardown is clean")
G.teardown(env)
empty("final")

-- wizard tab removed too
world(); G.init(env); F.lines("Aldric <wiz>: w", "x"); G.teardown(env); empty("teardown with wizard tab")

-- missing slot, then onLayout builds
world({ noSlot = true }); G.init(env)
eq(F.counts().objects, 1, "slot is the only object")
F.lines("Aldric [retro]: hi", "x")
eq(#events, 1, "onChat still raised without panel")
rmgui.layout = { get = function() return slot end }
F.fire("rmgui.onLayout", { layout = "wide" })
eq(tab("all") ~= nil, true, "built on onLayout")
F.fire("rmgui.onLayout", { layout = "wide" })
eq(F.counts().objects, 1 + 1 + 7 * 3 + 2, "second onLayout adds nothing (strip, slot, 7 tabs with image, text and console, 2 font buttons)")
G.teardown(env)
F.objects.slot:delete()
empty("teardown after late build")

-- layout.get raising
world(); rmgui.layout = { get = function() error("boom") end }
G.init(env)
eq(tab("all"), nil, "layout error: nothing built")
G.teardown(env)

-- failing Geyser calls
for _, key in ipairs({ "Container:new", "Label:new", "MiniConsole:new", "MiniConsole:hide" }) do
    world(); F.failOn = { [key] = true }
    local ok = pcall(G.init, env)
    eq(ok, true, "init survives " .. key)
    F.failOn = nil
    G.teardown(env)
    F.objects.slot:delete()
    empty("clean after " .. key)
end
-- failing echo/setBufferSize/click only degrade
world(); F.failOn = { ["Label:echo"] = true, ["MiniConsole:setBufferSize"] = true, ["Label:setStyleSheet"] = true }
eq(pcall(G.init, env), true, "init survives echo and buffer failures")
F.failOn = nil
rmgui.theme.apply("perdow", env, env.settings)
F.lines("Aldric [retro]: hi")
eq(txt("chat") ~= "", true, "still routes")
G.teardown(env)

-- theme.register missing: init must not raise
world(); local reg = rmgui.theme.register; rmgui.theme.register = nil
eq(pcall(G.init, env), true, "init without theme module")
rmgui.theme.register = reg
G.teardown(env)

-- copy failing and a throwing engine do not stop later lines
world(); G.init(env)
local c0 = copy; _G.copy = function() error("nope") end
F.lines("Aldric [retro]: hi")
_G.copy = c0
eq(txt("all") ~= "", true, "copy failure tolerated")
G.teardown(env)

-- registered with the lifecycle
eq(type(rmgui.chat.glue.init), "function", "module exposes init")

---------------------------------------------------------------- stream
world(); env.settings.chat.maxLines = 300; G.init(env)
local mixed = { "Aldric [retro]: hello there", "[info] Mirel goes linkdead", "Aldric (Party): go", "You [hit]: 12",
    "Aldric < (=Fighter=) > hi", "[welstar] horn", "      more words here", "Mirel telepathically contacts you with 'x'" }
local t0 = os.clock()
for i = 1, 5000 do F.feedLine(mixed[i % #mixed + 1]) end
local dt = os.clock() - t0
eq(dt < 5, true, "5000 lines stay fast (" .. ("%.2f"):format(dt) .. "s)")
eq(#F.objects["rmgui.chat.console.all"].lineBuffer <= 300, true, "buffer limit holds")
eq(#F.objects["rmgui.chat.console.all"].lineBuffer > 100, true, "buffer is used")
G.teardown(env)

---------------------------------------------------------------- review: file re-run, hostile maxLines
start()
dofile(root .. "/src/scripts/chat/glue.lua") -- the player saved the script again while it was live
G = rmgui.chat.glue
G.teardown(env)
local c = F.counts()
eq(c.objects - 1 + c.triggers + c.handlers, 0, "teardown after a file re-run leaves nothing (slot excluded)")
for _, v in ipairs({ 1e300, math.huge, 0 / 0, -5, 1.5, "x" }) do
    start(); env.settings.chat.maxLines = v; G.init(env)
    eq(F.objects["rmgui.chat.console.all"].maxLines, 2000, "maxLines " .. tostring(v) .. " falls back")
    G.teardown(env)
end

-- font size buttons
start()
local minus, plus = F.objects["rmgui.chat.font.1"], F.objects["rmgui.chat.font.2"]
eq(F.objects["rmgui.chat.console.all"].fontSize, 10, "default chat font is 10")
plus:fireClick()
eq(F.objects["rmgui.chat.console.all"].fontSize, 11, "A+ grows the font")
eq(env.settings.chat.fontSize, 11, "font size kept in the settings")
for _ = 1, 30 do minus:fireClick() end
eq(F.objects["rmgui.chat.console.all"].fontSize, 6, "A- stops at 6")
for _ = 1, 30 do plus:fireClick() end
eq(F.objects["rmgui.chat.console.all"].fontSize, 24, "A+ stops at 24")
env.settings.chat.fontSize = 14; G.init(env)
eq(F.objects["rmgui.chat.console.all"].fontSize, 14, "saved font size used")
env.settings.chat.fontSize = "big"; G.init(env)
eq(F.objects["rmgui.chat.console.all"].fontSize, 10, "bad saved font size falls back")


if COVER then
    debug.sethook()
    local path = root .. "/src/scripts/chat/glue.lua"
    local n = 0
    for l in io.lines(path) do
        n = n + 1
        local code = l:match("^%s*(.-)%s*$")
        local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$") or code:match("^local function")
            or code:match("^function ") or code:match("^[%]})]+,?$") or code:match("^elseif")
        if not skip and not hit[path .. ":" .. n] then print(("not run  glue.lua:%d  %s"):format(n, code)) end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
