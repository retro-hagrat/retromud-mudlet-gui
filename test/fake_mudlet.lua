-- Fake Mudlet world for offline tests. Plain Lua, no Mudlet.
--
--   local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
--   local F = dofile(root .. "/test/fake_mudlet.lua")
--   F.reset()      -- fresh world, fake globals installed into _G (originals remembered)
--   F.restore()    -- originals back in _G
--
-- Fake globals: Geyser (Label, Container, MiniConsole, Mapper, Gauge, StyleSheet), Adjustable.Container,
-- and the Mudlet functions: borders (get/set Border Top/Right/Bottom/Left, getBorderSizes, setBorderColor),
-- getMainWindowSize, calcFontSize, tempTimer/killTimer, registerAnonymousEventHandler/
-- killAnonymousEventHandler, raiseEvent, tempRegexTrigger/killTrigger, appendBuffer, copy, getCurrentLine,
-- deleteLine, selectCurrentLine, moveCursor, isPrompt, cecho, echo, getMudletHomeDir, getPackageInfo,
-- getPackages, installPackage, uninstallPackage, expandAlias, map colours (set/get MapBackgroundColor,
-- set/get MapRoomExitsColor), setCmdLineStyleSheet, table.save, table.load, plus io.open and loadfile
-- (they see F.files first, then the real file system). setBufferSize is NOT a global (as in Mudlet).
--
-- World state and helpers (all on F):
--   F.objects[name]            live Geyser object by name (the newest one if a name is used twice)
--   F.objectList               array of every live object (use F.counts().objects to find duplicates)
--   F.timers                   array of live timers { id, at, fn, every }; F.now = fake clock in seconds
--   F.runTimers(seconds)       advance the clock, run due timers in order (a timer may add timers)
--   F.handlers                 array of live { id, event, fn }
--   F.fire(event, ...)         call every handler of event in registration order as fn(event, ...)
--   F.aliases / F.sendAlias(text)  live temp aliases { id, pattern, fn }; sendAlias runs matching ones (Lua pattern)
--   F.triggers                 array of live { id, pattern, fn }
--   F.feedLine(text, opts)     an incoming line: sets current line, opts.prompt sets isPrompt(), runs every
--                              matching trigger. Pattern "^" matches every line; any other pattern is
--                              matched as a Lua pattern (shortcut: no PCRE, upgrade when a test needs it).
--   F.lines(...)               feedLine for each argument
--   F.counts()                 { objects =, triggers =, timers =, handlers = } live things
--   F.calls                    array of { fn = name, args = {...} } for every fake Mudlet global call
--   F.setWindowSize(w, h)      sets getMainWindowSize and raises sysWindowResizeEvent (event, w, h)
--   F.setCharSize(w, h)        sets calcFontSize("main")
--   F.packages                 name -> version string; getPackageInfo and getPackages read it
--   F.files                    path -> string (loadfile/io.open) or table (table.save/table.load)
--   F.output                   array of lines printed with cecho/echo (colour tags removed)
--   F.consoleText(name)        array of lines of a MiniConsole
--   F.borders                  { top, right, bottom, left }; F.mapBg, F.mapExits, F.borderColor, F.cmdlineCss
--   F.home                     what getMudletHomeDir returns
-- Object helpers: obj:fireClick(), obj:fireEnter(), obj:fireLeave(). Recorded object state: obj.styleSheet,
--   obj.text, obj.textColor, obj.hidden, obj.bgImage, obj.tooltip, obj.children (array), obj.parent.
--   Geometry: obj.x/.y/.width/.height as given (numbers become "Npx" strings like the real ones);
--   obj:get_x() ... get_height() return absolute pixels (numbers).
-- Real behaviour kept on purpose (checked in a live Mudlet 5.1.1): table.load RAISES on a missing file;
--   table.save returns nil, err on failure; killTimer/killTrigger return true then false; killAnonymousEvent-
--   Handler returns true, then nil + message; deleting a container deletes its children; deleting twice is
--   fine; an object with a used name is a second object; getPackageInfo(name, "version") is "" if unknown.
-- Test hooks: F.failOn = { ["Label:new"] = true, ["Label:echo"] = true, ... } makes that call raise
--   "fake failure" (class methods are keyed "Class:method"; Mudlet globals by name).

local F = {}
local real = {}      -- remembered originals
local installed = false

local function px(v)
    if type(v) == "number" then return v .. "px" end
    return v
end

-- resolve a size given as number, "12px" or "50%" against a total
local function dim(v, total)
    if type(v) == "number" then return v end
    if type(v) ~= "string" then return 0 end
    local n = tonumber(v:match("^(-?[%d.]+)%%$"))
    if n then return total * n / 100 end
    return tonumber(v:match("^(-?[%d.]+)px$")) or tonumber(v) or 0
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = copy(x) end
    return c
end

---------------------------------------------------------------- world
local W

local function failIf(key)
    if F.failOn and F.failOn[key] then error("fake failure: " .. key, 0) end
end

local function rec(fn, ...)
    failIf(fn)
    F.calls[#F.calls + 1] = { fn = fn, args = { ... } }
end

local function newWorld()
    W = {}
    F.calls, F.objects, F.objectList, F.timers, F.handlers, F.triggers = {}, {}, {}, {}, {}, {}
    F.aliases = {}
    F.output, F.files, F.packages, F.failOn = {}, {}, {}, nil
    F.now, F.nextId = 0, 0
    F.borders = { top = 0, right = 0, bottom = 0, left = 0 }
    F.mapBg, F.mapExits = { 0, 0, 0, 255 }, { 192, 192, 192 }
    F.borderColor, F.cmdlineCss = nil, nil
    F.home = "/fake/home"
    F.winW, F.winH, F.charW, F.charH = 1920, 904, 8, 15
    F.currentLine, F.prompt = "", false
    F.consoles = {}
end

local function nextId() F.nextId = F.nextId + 1; return F.nextId end

---------------------------------------------------------------- geometry and objects
local Root

local function newClass(typeName)
    local C = { typeName = typeName }
    C.__index = C
    return C
end

local Base = newClass("container")

local function parentBox(self)
    local p = self.parent
    -- Real Mudlet quirk (seen live): a child whose parent is an Adjustable.Container is positioned
    -- from the Inside area but sized in percent of the WHOLE container, so it overflows. Parent the
    -- children to container.Inside instead.
    if p and p.Inside then return p.Inside:get_x(), p.Inside:get_y(), p:get_width(), p:get_height() end
    if p and p ~= Root then return p:get_x(), p:get_y(), p:get_width(), p:get_height() end
    return 0, 0, F.winW, F.winH
end

function Base:get_x() local px0, _, pw = parentBox(self); return px0 + dim(self.x, pw) end
function Base:get_y() local _, py, _, ph = parentBox(self); return py + dim(self.y, ph) end
function Base:get_width() local _, _, pw = parentBox(self); return dim(self.width, pw) end
function Base:get_height() local _, _, _, ph = parentBox(self); return dim(self.height, ph) end

local function detach(self)
    local p = self.parent
    if p and p.children then
        for i, c in ipairs(p.children) do if c == self then table.remove(p.children, i) break end end
    end
end

local function attach(self, parent)
    parent = parent or Root
    self.parent = parent
    if parent.children then parent.children[#parent.children + 1] = self end
end

local function register(self)
    F.objectList[#F.objectList + 1] = self
    F.objects[self.name] = self
end

local function construct(C, cons, parent)
    cons = cons or {}
    failIf(C.className .. ":new")
    local o = setmetatable({}, C)
    for k, v in pairs(cons) do o[k] = v end
    o.name = cons.name or ("fake" .. nextId())
    o.type = C.typeName
    o.x, o.y = px(cons.x or 0), px(cons.y or 0)
    o.width, o.height = px(cons.width or "100%"), px(cons.height or "100%")
    o.hidden = false
    o.children = {}
    o.clickCallbacks = {}
    attach(o, parent) -- like the real Geyser: a container field in the table is ignored (a real bug hid behind it)
    register(o)
    return o
end

local function methodFail(self, m) failIf(self.className .. ":" .. m) end

function Base.new(C, cons, parent) return construct(C, cons, parent) end
function Base:hide() methodFail(self, "hide"); self.hidden = true end
function Base:show() methodFail(self, "show"); self.hidden = false end
function Base:raise() end
function Base:lower() end
function Base:reposition() end
function Base:move(x, y) methodFail(self, "move"); self.x, self.y = px(x), px(y) end
function Base:resize(w, h) methodFail(self, "resize"); self.width, self.height = px(w), px(h) end
function Base:addChild(c) c:changeContainer(self) end
function Base:changeContainer(p) detach(self); attach(self, p) end

function Base:delete()
    if self.deleted then return end
    self.deleted = true
    for i = #self.children, 1, -1 do self.children[i]:delete() end
    detach(self)
    for i, o in ipairs(F.objectList) do if o == self then table.remove(F.objectList, i) break end end
    if F.objects[self.name] == self then
        F.objects[self.name] = nil
        for _, o in ipairs(F.objectList) do if o.name == self.name then F.objects[self.name] = o end end
    end
end

local Container = newClass("container"); setmetatable(Container, { __index = Base }); Container.className = "Container"

local Label = newClass("label"); setmetatable(Label, { __index = Base }); Label.className = "Label"
function Label:echo(text, color, fmt)
    methodFail(self, "echo")
    self.text, self.textColor, self.textFormat = text, color, fmt
end
function Label:cecho(text) methodFail(self, "cecho"); self.text = text end
function Label:clear() self.text, self.textColor = nil, nil end
function Label:setStyleSheet(css) methodFail(self, "setStyleSheet"); self.styleSheet = css end
function Label:setBackgroundImage(path) methodFail(self, "setBackgroundImage"); self.bgImage = path end
function Label:resetBackgroundImage() self.bgImage = nil end
function Label:setClickCallback(fn, ...)
    methodFail(self, "setClickCallback")
    self.clickCallbacks.click = fn and { fn = fn, args = { ... } } or nil
end
function Label:setOnEnter(fn, ...) self.clickCallbacks.enter = fn and { fn = fn, args = { ... } } or nil end
function Label:setOnLeave(fn, ...) self.clickCallbacks.leave = fn and { fn = fn, args = { ... } } or nil end
function Label:setFgColor(...) self.fgColor = { ... } end
function Label:setFontSize(n) self.fontSize = n end
function Label:setAlignment(a) self.alignment = a end
function Label:setToolTip(text, dur) self.tooltip, self.tooltipDuration = text, dur end
local function fireCb(self, kind, ...)
    local cb = self.clickCallbacks[kind]
    if cb then
        local a = { table.unpack(cb.args) }
        for _, v in ipairs({ ... }) do a[#a + 1] = v end -- like Mudlet: the event comes last
        return cb.fn(table.unpack(a))
    end
end
function Label:fireClick(ev) return fireCb(self, "click", ev or { button = "LeftButton" }) end
function Label:fireRightClick() return fireCb(self, "click", { button = "RightButton" }) end
function Label:fireEnter() return fireCb(self, "enter") end
function Label:fireLeave() return fireCb(self, "leave") end

local MiniConsole = newClass("miniConsole"); setmetatable(MiniConsole, { __index = Base }); MiniConsole.className = "MiniConsole"
local function strip(s) return (tostring(s):gsub("<[%w_:,%.#]*>", "")) end
local function addText(self, text)
    local buf = self.lineBuffer
    local parts = {}
    for piece in (text .. "\n"):gmatch("(.-)\n") do parts[#parts + 1] = piece end
    -- text before the first "\n" continues the open line; a trailing "\n" leaves an empty open line
    buf[#buf] = (buf[#buf] or "") .. parts[1]
    for i = 2, #parts do buf[#buf + 1] = parts[i] end
    if self.maxLines then while #buf > self.maxLines do table.remove(buf, 1) end end
end
function MiniConsole:echo(text) methodFail(self, "echo"); addText(self, tostring(text)) end
function MiniConsole:cecho(text) methodFail(self, "cecho"); addText(self, strip(text)) end
function MiniConsole:clear() self.lineBuffer = { "" } end
function MiniConsole:setFontSize(n) self.fontSize = n end
function MiniConsole:setWrap(n) self.wrap = n end
function MiniConsole:enableAutoWrap() self.autoWrap = true end
function MiniConsole:setBufferSize(lines, deleteBatch) methodFail(self, "setBufferSize"); self.maxLines, self.deleteBatch = lines, deleteBatch end
function MiniConsole:appendBuffer() methodFail(self, "appendBuffer"); addText(self, F.currentLine .. "\n") end
function MiniConsole:setColor(...) self.color = { ... } end
function MiniConsole:getLineCount() return #self.lineBuffer end
function MiniConsole:scrollDown() end
function MiniConsole:enableScrollBar() self.scrollBar = true end
function MiniConsole:disableScrollBar() self.scrollBar = false end

local Mapper = newClass("mapper"); setmetatable(Mapper, { __index = Base }); Mapper.className = "Mapper"

local Gauge = newClass("gauge"); setmetatable(Gauge, { __index = Base }); Gauge.className = "Gauge"
function Gauge:setValue(cur, max, text) methodFail(self, "setValue"); self.value, self.max, self.valueText = cur, max, text end
function Gauge:setStyleSheet(front, back, text) methodFail(self, "setStyleSheet"); self.styleFront, self.styleBack, self.styleText = front, back, text end
function Gauge:setColor(...) self.color = { ... } end
function Gauge:setFontSize(n) self.fontSize = n end
function Gauge:setText(t) self.text = t end
function Gauge:echo(t, color) self.text, self.textColor = t, color end

local CommandLine = newClass("commandline"); setmetatable(CommandLine, { __index = Base }); CommandLine.className = "CommandLine"
function CommandLine:getText() methodFail(self, "getText"); return self.typed or "" end
function CommandLine:print(t) methodFail(self, "print"); self.typed = t end
function CommandLine:clear() self.typed = "" end
function CommandLine:setStyleSheet(css) methodFail(self, "setStyleSheet"); self.styleSheet = css end
function CommandLine:setAction(fn, ...) self.action = fn and { fn = fn, args = { ... } } or nil end
function CommandLine:enter() local a = self.action if a then return a.fn(table.unpack(a.args), self.typed) end end

local Adj = newClass("adjustablecontainer"); setmetatable(Adj, { __index = Base }); Adj.className = "Adjustable"
function Adj:attachToBorder(side)
    methodFail(self, "attachToBorder")
    local s = tostring(side):lower()
    local size = (s == "top" or s == "bottom") and self:get_height() or self:get_width()
    F.borders[s] = size
    self.attached = s
end
function Adj:adjustBorder() end
function Adj:setPadding(p)
    methodFail(self, "setPadding")
    self.padding = p
end
function Adj:changeMenuStyle(a, b) self.menuStyle = { a, b } end
function Adj:setTitle(text, color) methodFail(self, "setTitle"); self.title = text; self.titleColor = color end
function Adj:save() methodFail(self, "save"); F.files["adj:" .. self.name] = { x = self.x, y = self.y, width = self.width, height = self.height }; self.saved = true end
function Adj:load()
    methodFail(self, "load")
    local d = F.files["adj:" .. self.name]
    if d then self.x, self.y, self.width, self.height = d.x, d.y, d.width, d.height end
    self.loaded = true
end
function Adj:minimize() self.minimized = true end
function Adj:restore() self.minimized = false end
function Adj:delete()
    if self.autoSave ~= false and not self.deleted then pcall(self.save, self) end
    Base.delete(self)
end

local function part(owner, suffix, cons)
    cons.name = owner.name .. suffix
    return construct(Label, cons, owner)
end

-- gauge and adjustable containers own sub-labels like the real ones
local gaugeNew = construct
function Gauge.new(C, cons, parent)
    local g = gaugeNew(C, cons, parent)
    local function sub(suffix) local l = construct(Label, { name = g.name .. suffix, x = 0, y = 0, width = "100%", height = "100%" }, g); return l end
    g.back, g.front, g.text = sub("_back"), sub("_front"), sub("_text")
    return g
end
function Adj.new(C, cons, parent)
    cons = cons or {}
    local a = construct(C, cons, parent)
    a.adjLabel = part(a, "adjLabel", { x = 0, y = 0, width = "100%", height = 20 })
    a.minimizeLabel = part(a, "minimizeLabel", { x = -40, y = 0, width = 20, height = 20 })
    a.exitLabel = part(a, "exitLabel", { x = -20, y = 0, width = 20, height = 20 })
    a.title = cons.titleText
    a.padding = cons.padding or 10
    -- Inside area: padding on the left, right and bottom, twice the padding on top (measured live)
    local failOn = F.failOn
    F.failOn = nil -- the Inside area is part of the Adjustable, not a call the test code makes
    local inside = construct(Container, { name = a.name .. "InsideContainer", x = 0, y = 0, width = "100%", height = "100%" }, a)
    F.failOn = failOn
    inside.get_x = function() return a:get_x() + a.padding end
    inside.get_y = function() return a:get_y() + 2 * a.padding end
    inside.get_width = function() return a:get_width() - 2 * a.padding end
    inside.get_height = function() return a:get_height() - 3 * a.padding end
    a.Inside = inside
    if cons.autoLoad ~= false then a:load() end
    return a
end

---------------------------------------------------------------- Mudlet functions
local G = {}   -- fake globals

local function gfn(name, fn)
    G[name] = function(...) rec(name, ...); return fn(...) end
end

for _, side in ipairs({ "Top", "Right", "Bottom", "Left" }) do
    local key = side:lower()
    gfn("getBorder" .. side, function() return F.borders[key] end)
    gfn("setBorder" .. side, function(n) F.borders[key] = n end)
end
gfn("getBorderSizes", function() return { top = F.borders.top, right = F.borders.right, bottom = F.borders.bottom, left = F.borders.left } end)
gfn("setBorderColor", function(r, g, b) F.borderColor = { r, g, b } end)
gfn("getMainWindowSize", function() return F.winW, F.winH end)
gfn("calcFontSize", function() return F.charW, F.charH end)

gfn("tempTimer", function(sec, fn, repeating)
    local t = { id = nextId(), at = F.now + sec, fn = fn, every = repeating and sec or nil }
    F.timers[#F.timers + 1] = t
    return t.id
end)
gfn("killTimer", function(id)
    for i, t in ipairs(F.timers) do if t.id == id then table.remove(F.timers, i) return true end end
    return false
end)

gfn("registerAnonymousEventHandler", function(event, fn)
    local h = { id = nextId(), event = event, fn = fn }
    F.handlers[#F.handlers + 1] = h
    return h.id
end)
gfn("killAnonymousEventHandler", function(id)
    for i, h in ipairs(F.handlers) do if h.id == id then table.remove(F.handlers, i) return true end end
    return nil, ("Handler with ID '%s' not found."):format(tostring(id))
end)
gfn("raiseEvent", function(event, ...) F.fire(event, ...) end)

gfn("tempRegexTrigger", function(pattern, fn)
    local t = { id = nextId(), pattern = pattern, fn = fn }
    F.triggers[#F.triggers + 1] = t
    return t.id
end)
gfn("killTrigger", function(id)
    for i, t in ipairs(F.triggers) do if t.id == id then table.remove(F.triggers, i) return true end end
    return false
end)

gfn("tempAlias", function(pattern, fn)
    local a = { id = nextId(), pattern = pattern, fn = fn }
    F.aliases[#F.aliases + 1] = a
    return a.id
end)
gfn("killAlias", function(id)
    for i, a in ipairs(F.aliases) do if a.id == id then table.remove(F.aliases, i) return true end end
    return false
end)
-- F.sendAlias(text): runs every alias whose Lua pattern matches; matches are in the global `matches`
function F.sendAlias(text)
    local list = {}
    for i, a in ipairs(F.aliases) do list[i] = a end
    for _, a in ipairs(list) do
        local m = { text:match(a.pattern) }
        if m[1] ~= nil then matches = { text, table.unpack(m) }; a.fn() end
    end
end

gfn("appendBuffer", function(win)
    local c = F.objects[win]
    if c and c.appendBuffer then c:appendBuffer() end
end)
gfn("copy", function() F.copied = F.currentLine end)
-- copy2decho and decho: the text of the line with colour tags, written to a console without a line end.
-- Like Mudlet, decho strips only real colour tags and leaves other angle brackets (<chat>) alone.
gfn("copy2decho", function() return "<0,255,0:0,0,0>" .. F.currentLine .. "<r>" end)
gfn("decho", function(win, text)
    local c = F.objects[win]
    if c and c.echo then c:echo((tostring(text):gsub("<%d+,%d+,%d+:%d+,%d+,%d+>", ""):gsub("<r>", ""))) end
end)
gfn("getCurrentLine", function() return F.currentLine end)
gfn("deleteLine", function() F.currentLine = ""; F.lineDeleted = true end)
gfn("selectCurrentLine", function() return true end)
gfn("moveCursor", function() return true end)
gfn("isPrompt", function() return F.prompt end)
gfn("expandAlias", function(text) F.expanded = F.expanded or {}; F.expanded[#F.expanded + 1] = text; return true end)

local function out(text) F.output[#F.output + 1] = (strip(text):gsub("\n$", "")) end
gfn("cecho", out)
gfn("echo", out)

gfn("getMudletHomeDir", function() return F.home end)
gfn("getPackageInfo", function(name, field)
    if field == nil then return {} end
    if field == "version" then return F.packages[name] or "" end
    return ""
end)
gfn("getPackages", function()
    local t = {}
    for n in pairs(F.packages) do t[#t + 1] = n end
    table.sort(t)
    return t
end)
gfn("installPackage", function(path) F.installed = F.installed or {}; F.installed[#F.installed + 1] = path; return true end)
gfn("uninstallPackage", function(name) F.packages[name] = nil; return true end)

gfn("setMapBackgroundColor", function(r, g, b, a) F.mapBg = { r, g, b, a or 255 } end)
gfn("getMapBackgroundColor", function() return table.unpack(F.mapBg) end)
gfn("setMapRoomExitsColor", function(r, g, b) F.mapExits = { r, g, b } end)
gfn("getMapRoomExitsColor", function() return table.unpack(F.mapExits) end)
gfn("setCmdLineStyleSheet", function(win, css) F.cmdlineCss = css end)

-- table.save/load: an in-memory file system. Real table.load raises on a missing file and fills the table given.
local function tsave(path, tbl)
    if type(path) ~= "string" or path:find("/nofs/", 1, true) then return nil, tostring(path) .. ": No such file or directory" end
    F.files[path] = copy(tbl)
    return true
end
local function tload(path, into)
    local d = F.files[path]
    if type(d) ~= "table" then error("cannot open " .. tostring(path) .. ": No such file or directory", 0) end
    into = into or {}
    for k, v in pairs(copy(d)) do into[k] = v end
    return into
end

---------------------------------------------------------------- Geyser tables
local function makeGeyser()
    local g = {
        Label = Label, Container = Container, MiniConsole = MiniConsole, Mapper = Mapper, Gauge = Gauge, CommandLine = CommandLine,
        StyleSheet = { new = function(_, css) return { css = css, getCSS = function(s) return s.css end } end },
    }
    -- constructors: Class:new(cons, parent)
    Label.new, Container.new, MiniConsole.new, Mapper.new = Base.new, Base.new, Base.new, Base.new
    Gauge.new, Adj.new = Gauge.new, Adj.new
    MiniConsole.new = function(C, cons, parent)
        local o = construct(C, cons, parent)
        o.lineBuffer = { "" }
        return o
    end
    return g
end

---------------------------------------------------------------- world helpers
function F.fire(event, ...)
    local list = {}
    for i, h in ipairs(F.handlers) do list[i] = h end
    for _, h in ipairs(list) do
        local alive = false
        for _, x in ipairs(F.handlers) do if x == h then alive = true end end
        if alive and h.event == event then
            local fn = h.fn
            if type(fn) == "string" then fn = _G[fn] end
            if type(fn) == "function" then fn(event, ...) end
        end
    end
end

function F.runTimers(seconds)
    local target = F.now + seconds
    while true do
        local best
        for _, t in ipairs(F.timers) do
            if t.at <= target and (not best or t.at < best.at or (t.at == best.at and t.id < best.id)) then best = t end
        end
        if not best then break end
        F.now = math.max(F.now, best.at)
        if best.every then best.at = best.at + best.every
        else for i, t in ipairs(F.timers) do if t == best then table.remove(F.timers, i) break end end end
        local fn = best.fn
        if type(fn) == "string" then fn = _G[fn] end
        if type(fn) == "function" then fn() end
    end
    F.now = target
end

function F.feedLine(text, opts)
    F.currentLine = text
    F.prompt = opts and opts.prompt or false
    local list = {}
    for i, t in ipairs(F.triggers) do list[i] = t end
    for _, t in ipairs(list) do
        local alive = false
        for _, x in ipairs(F.triggers) do if x == t then alive = true end end
        if alive and (t.pattern == "^" or text:find(t.pattern)) then t.fn() end
    end
end

function F.lines(...)
    for _, l in ipairs({ ... }) do F.feedLine(l) end
end

function F.counts()
    return { objects = #F.objectList, triggers = #F.triggers, timers = #F.timers, handlers = #F.handlers, aliases = #F.aliases }
end

function F.consoleText(name)
    local o = F.objects[name]
    local t = {}
    for i, l in ipairs(o and o.lineBuffer or {}) do t[i] = l end
    return t
end

function F.setWindowSize(w, h) F.winW, F.winH = w, h; F.fire("sysWindowResizeEvent", w, h) end
function F.setCharSize(w, h) F.charW, F.charH = w, h end

---------------------------------------------------------------- install
local GLOBALS = { "Geyser", "Adjustable", "loadfile" }

function F.reset()
    if installed then F.restore() end
    newWorld()
    Root = { children = {}, name = "Geyser Root Window" }
    for _, k in ipairs(GLOBALS) do real[k] = _G[k] end
    real.table_save, real.table_load, real.io_open = table.save, table.load, io.open
    real.mudlet = {}
    for k in pairs(G) do real.mudlet[k] = _G[k] end
    for k, v in pairs(G) do _G[k] = v end
    _G.Geyser = makeGeyser()
    _G.Adjustable = { Container = Adj }
    table.save = function(...) rec("table.save", ...); return tsave(...) end
    table.load = function(...) rec("table.load", ...); return tload(...) end
    local realOpen = real.io_open
    io.open = function(path, mode)
        local d = F.files[path]
        if type(d) == "string" then
            local pos = 1
            return { read = function() local r = d:sub(pos); pos = #d + 1; return r end, close = function() end }
        elseif d ~= nil then
            return { read = function() return "" end, close = function() end }
        end
        return realOpen(path, mode)
    end
    local realLoadfile = real.loadfile
    _G.loadfile = function(path, mode, env)
        local d = F.files[path]
        if type(d) == "string" then return load(d, "=" .. path, "t", env or _G) end
        return realLoadfile(path, mode, env)
    end
    installed = true
    return F
end

function F.restore()
    if not installed then return end
    for _, k in ipairs(GLOBALS) do _G[k] = real[k] end
    for k in pairs(G) do _G[k] = real.mudlet[k] end
    table.save, table.load, io.open = real.table_save, real.table_load, real.io_open
    installed = false
end

return F
