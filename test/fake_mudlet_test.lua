-- Tests for the fake Mudlet world itself. Run from the repo root: lua test/fake_mudlet_test.lua
-- COVER=1 prints the lines of fake_mudlet.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local before = { Geyser = Geyser, loadfile = loadfile, tsave = table.save, open = io.open, tempTimer = tempTimer }
local F = dofile(root .. "/test/fake_mudlet.lua")

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

F.reset()
eq(type(Geyser.Label), "table", "Geyser installed")

---------------------------------------------------------------- geometry
local c = Geyser.Container:new({ name = "c", x = 100, y = 100, width = 400, height = 200 })
local k = Geyser.Label:new({ name = "k", x = "10%", y = "50%", width = "50%", height = "25%" }, c)
eq(k:get_x(), 140, "child x"); eq(k:get_y(), 200, "child y")
eq(k:get_width(), 200, "child w"); eq(k:get_height(), 50, "child h")
eq(c.x, "100px", "numbers stored as px strings")
local g = Geyser.Label:new({ name = "g", x = 5, y = 6, width = "50%", height = 30 }, k)
eq(g:get_x(), 145, "nested x"); eq(g:get_width(), 100, "nested percent of percent")
local top = Geyser.Label:new({ name = "top", x = 10, y = 20, width = "50%", height = 30 })
eq(top:get_width(), 960, "root percent uses window size")
local pxs = Geyser.Label:new({ name = "pxs", x = "7px", y = 0, width = "3px", height = "bad" })
eq(pxs:get_x(), 7, "px string"); eq(pxs:get_width(), 3, "px width"); eq(pxs:get_height(), 0, "unparsable is 0")
eq(Geyser.Label:new({ name = "plain" , width = "12"}):get_width(), 12, "bare number string")
eq(Geyser.Label:new({}).name:sub(1, 4), "fake", "unnamed object gets a name")
eq(Geyser.Label:new().type, "label", "no constructor table")
k:move(0, 0); k:resize(100, 20)
eq(k:get_x(), 100, "move"); eq(k:get_height(), 20, "resize")
k:move("10%", "0"); eq(k:get_x(), 140, "move percent")
c:raise(); c:lower(); c:reposition()

-- children, hide/show, changeContainer
eq(#c.children, 1, "container has a child")
local c2 = Geyser.Container:new({ name = "c2", x = 0, y = 0, width = 10, height = 10 })
k:changeContainer(c2); eq(#c.children, 0, "left old parent"); eq(k.parent, c2, "new parent")
c2:addChild(g); eq(g.parent, c2, "addChild")
k:hide(); eq(k.hidden, true, "hide"); k:show(); eq(k.hidden, false, "show")

-- label state
k:echo("hi", "#ff0000"); eq(k.text, "hi", "echo text"); eq(k.textColor, "#ff0000", "echo colour")
k:cecho("<red>x"); eq(k.text, "<red>x", "cecho")
k:clear(); eq(k.text, nil, "clear")
k:setStyleSheet("a"); eq(k.styleSheet, "a", "stylesheet")
k:setBackgroundImage("p.png"); eq(k.bgImage, "p.png", "bg image"); k:resetBackgroundImage(); eq(k.bgImage, nil, "reset image")
k:setToolTip("tip", 5); eq(k.tooltip, "tip", "tooltip")
k:setFgColor(1, 2, 3); k:setFontSize(9); k:setAlignment("left")
eq(k.fontSize, 9, "font size")
local clicked, ent, lev = 0, 0, 0
k:setClickCallback(function(a) clicked = clicked + a end, 2); k:fireClick(); eq(clicked, 2, "click with args")
k:setOnEnter(function() ent = ent + 1 end); k:fireEnter(); k:setOnLeave(function() lev = lev + 1 end); k:fireLeave()
eq(ent + lev, 2, "enter and leave")
k:setClickCallback(nil); k:fireClick(); eq(clicked, 2, "click removed")

-- delete: recursive, twice is fine, duplicate names
c2:delete(); c2:delete()
eq(F.objects.c2, nil, "deleted from objects"); eq(F.objects.k, nil, "child deleted with parent"); eq(F.objects.g, nil, "grandchild deleted")
local d1 = Geyser.Label:new({ name = "dup" }); local d2 = Geyser.Label:new({ name = "dup" })
eq(F.objects.dup, d2, "newest object by name")
d2:delete(); eq(F.objects.dup, d1, "older object back after delete"); d1:delete(); eq(F.objects.dup, nil, "gone")

---------------------------------------------------------------- console, gauge, mapper
local mc = Geyser.MiniConsole:new({ name = "mc", x = 0, y = 0, width = 100, height = 100 })
mc:echo("one\ntwo"); mc:echo("-x\n"); mc:cecho("<red>three\n")
local t = F.consoleText("mc")
eq(t[1], "one", "console line 1"); eq(t[2], "two-x", "console line 2 continued"); eq(t[3], "three", "cecho stripped"); eq(mc:getLineCount(), 4, "open line counts")
mc:setBufferSize(2, 1); mc:echo("x\ny"); eq(#F.consoleText("mc"), 2, "buffer limit")
mc:clear(); F.feedLine("from game"); appendBuffer("mc"); mc:appendBuffer(); eq(F.consoleText("mc")[1], "from game", "appendBuffer copies current line")
appendBuffer("nowhere")
mc:clear(); eq(#F.consoleText("mc"), 1, "clear"); eq(F.consoleText("none")[1], nil, "unknown console")
mc:setFontSize(8); mc:setWrap(80); mc:enableAutoWrap(); mc:setColor(0, 0, 0); mc:scrollDown(); mc:enableScrollBar(); mc:disableScrollBar()
eq(mc.scrollBar, false, "scrollbar")
local ga = Geyser.Gauge:new({ name = "ga", x = 0, y = 0, width = 100, height = 10 })
ga:setValue(3, 10, "3/10"); eq(ga.value, 3, "gauge value"); eq(ga.valueText, "3/10", "gauge text")
ga:setStyleSheet("f", "b", "t"); eq(ga.styleBack, "b", "gauge sheet")
ga:setColor(1, 1, 1); ga:setFontSize(7); ga:setText("t"); ga:echo("e", "#000"); eq(ga.text, "e", "gauge echo")
eq(F.objects.ga_front ~= nil, true, "gauge has front label")
ga:delete(); eq(F.objects.ga_front, nil, "gauge parts deleted")
local mp = Geyser.Mapper:new({ name = "mp" }); eq(mp.type, "mapper", "mapper")
eq(Geyser.StyleSheet:new("x"):getCSS(), "x", "stylesheet class")

---------------------------------------------------------------- adjustable
F.reset()
local a = Adjustable.Container:new({ name = "a", x = 0, y = 0, width = 200, height = 100, autoSave = false, autoLoad = false })
eq(a.loaded, nil, "autoLoad false does not load")
eq(a.adjLabel.name, "aadjLabel", "adjLabel name"); eq(F.objects.aminimizeLabel ~= nil, true, "minimizeLabel"); eq(a.exitLabel.type, "label", "exitLabel")
a:attachToBorder("top"); eq(getBorderTop(), 100, "attach top"); eq(a.attached, "top", "attached side")
a:attachToBorder("Left"); eq(getBorderLeft(), 200, "attach left")
a:setTitle("T"); eq(a.title, "T", "title"); a:changeMenuStyle("a", "b"); eq(a.menuStyle[2], "b", "menu style")
a:adjustBorder(); a:minimize(); eq(a.minimized, true, "minimize"); a:restore(); eq(a.minimized, false, "restore")
a:save(); a.width = 5; a:load(); eq(a.width, "200px", "save and load round trip")
a:delete(); eq(F.counts().objects, 0, "adjustable and parts deleted"); eq(a.saved, true, "save on explicit save")
local a2 = Adjustable.Container:new({ name = "a" })
eq(a2.loaded, true, "autoLoad by default loads"); eq(a2.width, "200px", "restored size")
a2:delete(); eq(a2.saved, true, "autoSave by default saves on delete")
local a3 = Adjustable.Container:new({ name = "a3", titleText = "tt", autoSave = false, autoLoad = false })
eq(a3.title, "tt", "titleText"); a3:delete(); eq(a3.saved, nil, "autoSave false")

---------------------------------------------------------------- events
F.reset()
local seen = {}
local h1 = registerAnonymousEventHandler("ev", function(e, x) seen[#seen + 1] = "a" .. tostring(x) end)
local h2 = registerAnonymousEventHandler("ev", function(e, x) seen[#seen + 1] = "b" .. tostring(x) end)
registerAnonymousEventHandler("other", function() seen[#seen + 1] = "other" end)
rmgui_probe_fn = function() seen[#seen + 1] = "named" end
registerAnonymousEventHandler("ev", "rmgui_probe_fn"); registerAnonymousEventHandler("ev", "no_such_fn")
raiseEvent("ev", 1); eq(table.concat(seen, ","), "a1,b1,named", "handlers in order")
F.fire("ev", 2); eq(#seen, 6, "fire")
eq(killAnonymousEventHandler(h1), true, "kill handler"); local ok, msg = killAnonymousEventHandler(h1)
eq(ok, nil, "kill twice nil"); eq(msg:find("not found", 1, true) ~= nil, true, "kill twice message")
-- a handler that kills a later handler: the killed one does not run
seen = {}
local h4
registerAnonymousEventHandler("kill", function() killAnonymousEventHandler(h4) end)
h4 = registerAnonymousEventHandler("kill", function() seen[#seen + 1] = "no" end)
F.fire("kill"); eq(#seen, 0, "killed during fire does not run")
eq(F.counts().handlers, 5, "handler count")
rmgui_probe_fn = nil

---------------------------------------------------------------- timers
F.reset()
local order = {}
tempTimer(2, function() order[#order + 1] = "b" end)
tempTimer(1, function() order[#order + 1] = "a"; tempTimer(0.5, function() order[#order + 1] = "nested" end) end)
local t3 = tempTimer(3, function() order[#order + 1] = "never" end)
local ev = tempTimer(1, function() order[#order + 1] = "r" end, true)
tempTimer(1, "rmgui_probe_tfn"); tempTimer(1, "no_such_fn")
rmgui_probe_tfn = function() order[#order + 1] = "s" end
eq(killTimer(t3), true, "kill timer"); eq(killTimer(t3), false, "kill timer twice")
F.runTimers(2.5)
eq(table.concat(order, ","), "a,r,s,nested,b,r", "timer order, nested and repeating")
eq(F.now, 2.5, "clock advanced"); eq(F.counts().timers, 1, "only the repeating timer is left")
rmgui_probe_tfn = nil

---------------------------------------------------------------- triggers and lines
F.reset()
local got = {}
local tr = tempRegexTrigger("^", function() got[#got + 1] = getCurrentLine() .. (isPrompt() and "!" or "") end)
tempRegexTrigger("^You", function() got[#got + 1] = "you" end)
local kt
kt = tempRegexTrigger("^", function() killTrigger(kt) end)
F.feedLine("You see a cat"); F.feedLine("prompt>", { prompt = true }); F.lines("x", "y")
eq(table.concat(got, ","), "You see a cat,you,prompt>!,x,y", "triggers and prompt flag")
eq(F.counts().triggers, 2, "self-killing trigger gone")
eq(killTrigger(tr), true, "kill trigger"); eq(killTrigger(tr), false, "kill trigger twice")
local late
tempRegexTrigger("^", function() killTrigger(late) end); late = tempRegexTrigger("^", function() got[#got + 1] = "late" end)
got = {}; F.feedLine("z"); eq(#got, 0, "trigger killed by an earlier one does not run")
deleteLine(); eq(F.currentLine, "", "deleteLine"); eq(F.lineDeleted, true, "deleteLine flag")
F.feedLine("copy me"); copy(); eq(F.copied, "copy me", "copy"); eq(selectCurrentLine(), true, "select"); eq(moveCursor("main", 0, 0), true, "moveCursor")

---------------------------------------------------------------- borders, colours, window
F.reset()
eq(getBorderTop() + getBorderRight() + getBorderBottom() + getBorderLeft(), 0, "borders start at 0")
setBorderTop(1); setBorderRight(2); setBorderBottom(3); setBorderLeft(4)
eq(getBorderTop() * 1000 + getBorderRight() * 100 + getBorderBottom() * 10 + getBorderLeft(), 1234, "border setters and getters")
local bs = getBorderSizes(); eq(bs.bottom, 3, "getBorderSizes")
setBorderColor(1, 2, 3); eq(F.borderColor[3], 3, "border colour")
setMapBackgroundColor(1, 2, 3); local r, gg, b, al = getMapBackgroundColor(); eq(r + gg + b + al, 261, "map bg default alpha")
setMapBackgroundColor(1, 2, 3, 4); eq(select(4, getMapBackgroundColor()), 4, "map bg alpha")
setMapRoomExitsColor(9, 8, 7); eq(select(2, getMapRoomExitsColor()), 8, "exits colour")
setCmdLineStyleSheet("main", "css"); eq(F.cmdlineCss, "css", "cmdline css")
local w, h = getMainWindowSize(); eq(w .. "x" .. h, "1920x904", "window size")
local resized
registerAnonymousEventHandler("sysWindowResizeEvent", function(e, w2, h2) resized = e .. w2 .. "," .. h2 end)
F.setWindowSize(800, 600); eq(resized, "sysWindowResizeEvent800,600", "resize event"); eq(select(2, getMainWindowSize()), 600, "new size")
eq(Geyser.Label:new({ width = "50%" }):get_width(), 400, "percent follows window")
eq(calcFontSize("main"), 8, "char width"); F.setCharSize(9, 16); eq(select(2, calcFontSize("main")), 16, "char height")
eq(getMudletHomeDir(), "/fake/home", "home")

---------------------------------------------------------------- packages, output, alias
F.packages.zeta = "1.0"; F.packages.alpha = "2.0"
eq(getPackageInfo("zeta", "version"), "1.0", "package version"); eq(getPackageInfo("nope", "version"), "", "unknown package")
eq(getPackageInfo("zeta", "title"), "", "other field"); eq(type(getPackageInfo("zeta")), "table", "no field gives table")
eq(table.concat(getPackages(), ","), "alpha,zeta", "getPackages sorted")
installPackage("/x.mpackage"); eq(F.installed[1], "/x.mpackage", "install"); uninstallPackage("zeta"); eq(F.packages.zeta, nil, "uninstall")
cecho("<red>hello\n"); echo("plain"); eq(F.output[1] .. "|" .. F.output[2], "hello|plain", "output captured")
eq(expandAlias("go north"), true, "expandAlias"); eq(F.expanded[1], "go north", "alias text")
eq(isPrompt(), false, "isPrompt default")

---------------------------------------------------------------- files
F.reset()
local into = {}
eq(table.save("/home/x.lua", { a = { b = 1 } }), true, "table.save")
eq(table.load("/home/x.lua", into).a.b, 1, "table.load"); eq(into.a.b, 1, "load fills table")
F.files["/home/x.lua"].a.b = 2; eq(table.load("/home/x.lua").a.b, 2, "load without table")
local okL, errL = pcall(table.load, "/missing.lua"); eq(okL, false, "load missing raises"); eq(errL:find("No such file", 1, true) ~= nil, true, "load error text")
local sv, serr = table.save("/nofs/x.lua", {}); eq(sv, nil, "save failure nil"); eq(serr:find("No such file", 1, true) ~= nil, true, "save failure text")
eq(select(1, table.save(5, {})), nil, "save bad path")
F.files["/o/theme.lua"] = "return { a = 1, g = tostring }"
local f = io.open("/o/theme.lua"); eq(f:read("*a"), "return { a = 1, g = tostring }", "io.open string file"); f:close()
local f2 = io.open("/home/x.lua"); eq(f2:read("*a"), "", "io.open table file exists"); f2:close()
eq(io.open("/definitely/not/here/rmgui"), nil, "io.open falls through to real fs")
local chunk = loadfile("/o/theme.lua", "t", {}); eq(chunk().a, 1, "loadfile reads fake file in given env")
eq(chunk().g, nil, "empty env")
eq(loadfile("/definitely/not/here/rmgui"), nil, "loadfile falls through")

---------------------------------------------------------------- failOn, calls
F.reset()
F.failOn = { ["Label:new"] = true, ["Label:echo"] = true, setBorderTop = true }
eq(pcall(Geyser.Label.new, Geyser.Label, {}), false, "failing constructor")
eq(pcall(setBorderTop, 5), false, "failing global")
F.failOn = { ["Label:echo"] = true }
local lb = Geyser.Label:new({ name = "lb" }); eq(pcall(lb.echo, lb, "x"), false, "failing method")
F.failOn = nil
setBorderTop(7); eq(F.calls[#F.calls].fn, "setBorderTop", "calls recorded"); eq(F.calls[#F.calls].args[1], 7, "call args recorded")

---------------------------------------------------------------- counts and restore
F.reset()
Geyser.Label:new({ name = "q" }); tempTimer(1, function() end); registerAnonymousEventHandler("e", function() end); tempRegexTrigger("^", function() end)
local n = F.counts(); eq(n.objects + n.timers + n.handlers + n.triggers, 4, "counts")
F.reset(); n = F.counts(); eq(n.objects + n.timers + n.handlers + n.triggers, 0, "reset clears the world")
F.restore(); F.restore()
eq(Geyser, before.Geyser, "Geyser restored"); eq(loadfile, before.loadfile, "loadfile restored")
eq(table.save, before.tsave, "table.save restored"); eq(io.open, before.open, "io.open restored"); eq(tempTimer, before.tempTimer, "mudlet function restored")

if COVER then
    debug.sethook()
    local src, miss = root .. "/test/fake_mudlet.lua", {}
    local n2 = 0
    for line in io.lines(src) do
        n2 = n2 + 1
        local code = line:gsub("%-%-.*$", "")
        if code:match("%S") and not code:match("^%s*end[%s,%)]*$") and not code:match("^%s*else%s*$") and not code:match("^%s*[%}%)]+,?%s*$")
            and not hit[arg[0]:gsub("test/.*", "") .. "test/fake_mudlet.lua:" .. n2] and not hit[src .. ":" .. n2] and not hit["test/fake_mudlet.lua:" .. n2] then
            miss[#miss + 1] = n2
        end
    end
    print("lines never run: " .. table.concat(miss, " "))
end
print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
