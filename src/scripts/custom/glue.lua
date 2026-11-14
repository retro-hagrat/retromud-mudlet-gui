-- custom/glue: twelve player buttons (3 rows of 4) in the "custom" layout slot under the chat.
-- A click sends the command with expandAlias: a matching Mudlet alias runs, else the text goes to the game.
-- A right click (or a click on an empty button) opens a small editor over the pane.
rmgui = rmgui or {}
rmgui.custom = rmgui.custom or {}
local C = rmgui.custom
C.state = C.state or {}
-- the editor re-runs this file while the old instance is live: stop it (its locals are unreachable later), restart below
local prevEnv = C.state.env
if C.teardown then pcall(C.teardown) end

local PREFIX = "rmgui.custom."
local ELEMENT = "custom.buttons"
local st = C.state

local function reset()
    for k in pairs(st) do st[k] = nil end
    st.labels, st.editor, st.ids, st.slots, st.said = {}, {}, {}, {}, {}
end
reset()

local function say(msg, level)
    if st.env and type(st.env.say) == "function" then pcall(st.env.say, msg, level) end
end

local function report(where, err)
    local msg = where .. ": " .. tostring(err)
    if st.said[msg] then return end
    st.said[msg] = true
    say(msg, "err")
end

local function del(o) if o then pcall(o.delete, o) end end
local function rgb(c) return ("rgb(%d,%d,%d)"):format(c[1], c[2], c[3]) end
local function hex(c) return ("#%02X%02X%02X"):format(c[1], c[2], c[3]) end

-- a Geyser click callback gets the Mudlet event as its last argument: { button = "RightButton", ... }
local function isRight(...)
    for i = 1, select("#", ...) do
        local a = select(i, ...)
        if type(a) == "table" and a.button == "RightButton" then return true end
    end
    return false
end

local function save()
    local s = st.env and st.env.settings
    if type(s) ~= "table" then return end
    s.custom = C.encode(st.slots)
    local ok, err = pcall(st.env.saveSettings)
    if not ok then report("save", err) end
end

---------------------------------------------------------------- drawing
local function look(muted)
    local th = st.ctx and st.ctx.theme
    if not th then return nil end
    local c = th.colors
    return ("QLabel{background-color: %s; color: %s; border: 1px solid %s; font-size: %dpt;}"):format(
        rgb(c.surfaceAlt), rgb(muted and c.textMuted or c.text), rgb(c.border), th.fonts.sizeSmall or th.fonts.size)
end

local function draw(n)
    local l = st.labels[n]
    if not l then return end
    pcall(function()
        local slot = st.slots[n]
        local th = st.ctx and st.ctx.theme
        local style = look(slot == nil)
        if style then l:setStyleSheet(style) end
        local color = th and hex(slot and th.colors.text or th.colors.textMuted) or nil
        l:echo(slot and slot.label or "+", color, "c")
        l:setToolTip(slot and (slot.command .. "\n(right click to edit)") or "Right click to set a button")
    end)
end

local function drawAll() for n = 1, C.COUNT do draw(n) end end

---------------------------------------------------------------- the editor
local function closeEditor()
    for _, o in ipairs(st.editor) do del(o) end
    st.editor, st.editing = {}, nil
end

local function mk(cls, cons, parent)
    local ok, o = pcall(cls.new, cls, cons, parent)
    if not ok or not o then report("editor", o) return nil end
    st.editor[#st.editor + 1] = o
    return o
end

local function fieldStyle()
    local th = st.ctx and st.ctx.theme
    if not th then return nil end
    local c = th.colors
    return ("background-color: %s; color: %s; border: 1px solid %s; font-size: %dpt;"):format(
        rgb(c.surface), rgb(c.text), rgb(c.border), th.fonts.size)
end

local function openEditor(n)
    closeEditor()
    local parent = st.slot
    if not parent then return end
    st.editing = n
    local cur = st.slots[n] or {}
    local back = mk(Geyser.Label, { name = PREFIX .. "editor", x = 0, y = 0, width = "100%", height = "100%" }, parent)
    if not back then closeEditor() return end
    local style = look(false)
    if style then pcall(back.setStyleSheet, back, style) end
    local function caption(name, text, y)
        local l = mk(Geyser.Label, { name = PREFIX .. "editor." .. name, x = 0, y = y, width = "26%", height = "24%" }, parent)
        if not l then return end
        pcall(l.setStyleSheet, l, "QLabel{background-color: transparent; border: none;}")
        pcall(l.echo, l, text, st.ctx and st.ctx.textColor("panel") or nil, "r")
    end
    caption("c1", "Name ", "3%"); caption("c2", "Command ", "30%")
    local function field(name, y, value)
        local f = mk(Geyser.CommandLine, { name = PREFIX .. "editor." .. name, x = "27%", y = y, width = "71%", height = "24%" }, parent)
        if not f then return nil end
        local fs = fieldStyle()
        if fs then pcall(f.setStyleSheet, f, fs) end
        pcall(f.print, f, value or "")
        return f
    end
    st.fName, st.fCommand = field("name", "3%", cur.label), field("command", "30%", cur.command)
    local function button(name, text, x, fn)
        local b = mk(Geyser.Label, { name = PREFIX .. "editor." .. name, x = x, y = "62%", width = "31%", height = "34%" }, parent)
        if not b then return end
        if style then pcall(b.setStyleSheet, b, style) end
        pcall(b.echo, b, text, st.ctx and st.ctx.textColor("button") or nil, "c")
        pcall(b.setClickCallback, b, function() local ok, err = pcall(fn) if not ok then report(name, err) end end)
    end
    local function text(f) local ok, t = pcall(f.getText, f) return ok and t or "" end
    local function done(label, command)
        local ok, why = C.set(st.slots, n, label, command)
        if not ok then say(why, "warn") return end
        save(); closeEditor(); drawAll()
    end
    button("save", "Save", "1%", function() done(text(st.fName), text(st.fCommand)) end)
    button("clear", "Clear", "34%", function() done("", "") end)
    button("cancel", "Cancel", "67%", closeEditor)
    for _, f in ipairs({ st.fName, st.fCommand }) do
        if f then pcall(f.setAction, f, function() done(text(st.fName), text(st.fCommand)) end) end
    end
end

---------------------------------------------------------------- clicking
local function click(n, ...)
    local slot = st.slots[n]
    if slot and not isRight(...) then
        local ok, err = pcall(st.env.expandAlias, slot.command)
        if not ok then report("send", err) end
        return
    end
    openEditor(n)
end

local function build()
    local ok, slot = pcall(function() return rmgui.layout and rmgui.layout.get("custom") end)
    if not ok or not slot then return end
    if st.slot == slot and next(st.labels) then return end
    closeEditor()
    for _, l in pairs(st.labels) do del(l) end
    st.labels, st.slot = {}, slot
    for n = 1, C.COUNT do
        local row, col = math.floor((n - 1) / C.COLS), (n - 1) % C.COLS
        local made, l = pcall(Geyser.Label.new, Geyser.Label, {
            name = PREFIX .. "button." .. n, x = (col * 25.2) .. "%", y = (row * 34) .. "%", width = "24.4%", height = "32%",
        }, slot)
        if made and l then
            st.labels[n] = l
            pcall(l.setClickCallback, l, function(...) local o, err = pcall(click, n, ...) if not o then report("click", err) end end)
        else
            report("button", l)
        end
    end
    drawAll()
end

function C.init(env)
    C.teardown()
    if type(env) ~= "table" then return end
    st.env = env
    local s = type(env.settings) == "table" and env.settings.custom
    local slots, dropped = C.decode(s)
    st.slots = slots
    if dropped > 0 then say(dropped .. " saved button(s) were not valid and were left out", "warn") end
    pcall(rmgui.theme.register, ELEMENT, function(ctx) st.ctx = ctx; closeEditor(); drawAll() end)
    local ok, id = pcall(env.registerEvent, "rmgui.onLayout", function() build() end)
    if ok and id then st.ids[#st.ids + 1] = id end
    build()
end

function C.teardown()
    closeEditor()
    for _, l in pairs(st.labels or {}) do del(l) end
    if st.env then
        for _, id in ipairs(st.ids) do pcall(st.env.killEvent, id) end
    end
    if rmgui.theme and rmgui.theme.unregister then pcall(rmgui.theme.unregister, ELEMENT) end
    reset()
end

rmgui.core.register("custom", { init = C.init, teardown = C.teardown })
if prevEnv then pcall(C.init, prevEnv) end
