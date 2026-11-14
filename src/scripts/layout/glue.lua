-- layout/glue: the frame (status bar, two columns, panels) as Geyser and Adjustable objects.
-- See doc/spec/layout.md. Sizes come from rmgui.layout.calc. This is the one module that calls the
-- border globals directly (the env has no border functions).
--
-- shortcut: borders are set explicitly from calc after attachToBorder, so the Adjustable class and
-- the explicit values can disagree until the player drags a container; upgrade when the live
-- behaviour of attachToBorder is known.
rmgui = rmgui or {}
rmgui.layout = rmgui.layout or {}
local L = rmgui.layout

local PREFIX = "rmgui.layout."
local PAD = 4 -- Adjustable padding in pixels
local GAP, FRAME, MIN_PANEL = 4, 16, 48
local BUTTONS_H = 72 -- panel height of the button row: the buttons inside are 40 px after the 16 px frame
local PICKER_W = 144 -- right end of the status bar, reserved for the theme picker button
local SLOTS = { "chat", "map", "vitals", "buttons" }
local SIDES = { "Top", "Right", "Bottom", "Left" }

-- live state; emptied in place by teardown. Kept on rmgui so that running this file again (the player
-- saves it in the editor) still sees the old objects and can remove them.
L.state = L.state or {}
local S = L.state
local function wipe() for k in pairs(S) do S[k] = nil end end

local function say(msg, level)
    if S.env and type(S.env.say) == "function" then pcall(S.env.say, msg, level) end
end

local function scale()
    local s = S.scale
    return (type(s) == "number" and s >= 1) and s or 1
end

local function track(obj)
    S.objs[#S.objs + 1] = obj
    return obj
end

-- Children go into the Inside area of an Adjustable.Container: given the container itself,
-- Mudlet positions them inside but sizes their percentages against the whole container.
local function inner(parent) return parent.Inside or parent end

local function label(name, parent, cons)
    parent = inner(parent)
    cons.name = PREFIX .. name
    cons.x, cons.y = cons.x or 0, cons.y or 0
    cons.width, cons.height = cons.width or "100%", cons.height or "100%"
    -- the parent is the SECOND argument: Geyser ignores a container field in the table
    return track(Geyser.Label:new(cons, parent))
end

local function box(name, parent)
    return track(Geyser.Container:new({ name = PREFIX .. name, x = 0, y = 0, width = "100%", height = "100%" }, parent))
end

local function column(name, side, pad)
    local c = track(Adjustable.Container:new({
        name = PREFIX .. name, x = 0, y = 0, width = 10, height = 10, autoSave = false, autoLoad = false,
    }))
    pcall(c.attachToBorder, c, side)
    pcall(c.setTitle, c, " ")
    pcall(c.setPadding, c, pad) -- a thin edge the player can still grab to resize
    for _, part in ipairs({ "minimizeLabel", "exitLabel" }) do
        local l = c[part]
        if l then pcall(l.hide, l) end -- the small title buttons only clutter the frame
    end
    return c
end

local function build()
    local leftCol, rightCol = column("leftCol", "left", PAD), column("rightCol", "right", PAD)
    S.leftCol, S.rightCol = leftCol, rightCol
    S.leftBg = label("leftBg", leftCol, {})
    S.rightBg = label("rightBg", rightCol, {})
    S.topBar = column("topBar", "top", 0) -- no padding: 3 x PAD would squeeze the 36 px bar
    S.topLabel = label("top", S.topBar, {})
    S.panels, S.inner = {}, {}
    S.inner.top = box("top.inner", S.topLabel)
    S.inner.picker = box("picker.inner", S.topLabel)
    for i, slot in ipairs(SLOTS) do
        S.panels[slot] = label(slot, i == 1 and leftCol or rightCol, {})
        S.inner[slot] = box(slot .. ".inner", S.panels[slot])
    end
    S.built = true
end

-- inner container of a framed panel: inset by the frame, in pixels
local function place(obj, x, y, w, h)
    obj:move(x, y)
    obj:resize(w, h)
end

local function panel(slot, y, w, h) -- w, h: the Inside size of the column
    local f = FRAME * scale()
    place(S.panels[slot], 0, y, w, h)
    place(S.inner[slot], f, f, math.max(w - 2 * f, 1), math.max(h - 2 * f, 1))
end

local function setBorders(t, r, b, l)
    setBorderTop(t); setBorderRight(r); setBorderBottom(b); setBorderLeft(l)
end

local function layoutNow(r)
    local W, H = S.W, S.H
    local f, k = FRAME * scale(), scale()
    place(S.topBar, 0, 0, W, r.top)
    place(S.topLabel, 0, 0, W, r.top)
    local ih = math.max(r.top - 16 * k, 1)
    place(S.inner.top, f, 8 * k, math.max(W - 2 * f - PICKER_W, 1), ih)
    place(S.inner.picker, math.max(W - f - PICKER_W, 0), 8 * k, PICKER_W, ih)
    if r.layout == "compact" then
        S.leftCol:hide(); S.rightCol:hide()
        setBorders(r.top, 0, r.bottom, 0)
        return
    end
    local colH = math.max(H - r.top - r.bottom, 3 * MIN_PANEL)
    -- children live in the Inside area: padding on the sides and bottom, twice the padding on top
    local lw, rw, ih = math.max(r.left - 2 * PAD, 1), math.max(r.right - 2 * PAD, 1), math.max(colH - 3 * PAD, 1)
    S.leftCol:show(); S.rightCol:show()
    place(S.leftCol, 0, r.top, r.left, colH)
    place(S.leftBg, 0, 0, lw, ih)
    place(S.rightCol, W - r.right, r.top, r.right, colH)
    place(S.rightBg, 0, 0, rw, ih)
    panel("chat", 0, lw, ih)
    local avail = ih - 2 * GAP
    local map = math.max(MIN_PANEL, math.floor(avail * 0.5))
    local btn = math.floor(BUTTONS_H * k) -- one slim row of buttons right under the map
    local vit = math.max(MIN_PANEL, avail - map - btn)
    panel("map", 0, rw, map)
    panel("buttons", map + GAP, rw, btn)
    panel("vitals", map + btn + 2 * GAP, rw, vit)
    setBorders(r.top, r.right, r.bottom, r.left)
end

function L.apply()
    local env = S.env
    if not env then return nil end
    local ok, res = pcall(function()
        if not S.built then error("no objects", 0) end
        local W, H = env.windowSize()
        local cfg = type(env.settings) == "table" and env.settings.layout
        if type(cfg) ~= "table" then cfg = {} end
        S.W, S.H = W or 0, H or 0
        local r = L.calc({
            windowWidth = W, windowHeight = H, charWidth = env.charWidth(),
            mode = cfg.mode, saved = cfg,
        })
        layoutNow(r)
        return r
    end)
    if not ok then
        say("layout failed: " .. tostring(res), "err")
        res = { layout = "compact", failed = true }
        if S.built then pcall(setBorders, 0, 0, 0, 0) end -- do not leave the stub sizes of the columns
    end
    pcall(env.raise, "rmgui.onLayout", res)
    return res
end

function L.get(slot)
    if not S.built then return nil end
    return S.inner[slot]
end

function L.command(argString, env)
    env = type(env) == "table" and env or S.env or {}
    local arg = tostring(argString or ""):match("^%s*(.-)%s*$"):lower()
    local function out(m, lvl) if type(env.say) == "function" then pcall(env.say, m, lvl) end end
    if arg ~= "wide" and arg ~= "compact" and arg ~= "auto" then
        out("usage: rgui layout wide|compact|auto")
        return false
    end
    local cfg = type(env.settings) == "table" and env.settings.layout
    if type(cfg) == "table" then
        cfg.mode = arg
        if type(env.saveSettings) == "function" then pcall(env.saveSettings) end
    end
    local r = L.apply()
    out("layout mode: " .. arg .. (r and (" (now " .. r.layout .. ")") or ""))
    return true
end

local function rgb(c) return ("rgb(%d,%d,%d)"):format(c[1], c[2], c[3]) end

local function theming(ctx)
    local t = ctx.theme
    if type(t) == "table" and type(t.imageScale) == "number" and t.imageScale ~= S.scale then
        S.scale = t.imageScale
        S.restyle = true
    end
    if not S.built then return end
    local function css(obj, role) pcall(obj.setStyleSheet, obj, ctx.css(role)) end
    if type(t) == "table" and type(t.colors) == "table" then -- the thin edge of each container
        local frame = ("QLabel{background-color: %s; border: 1px solid %s;}"):format(rgb(t.colors.surface), rgb(t.colors.border))
        for _, col in ipairs({ S.topBar, S.leftCol, S.rightCol }) do
            if col and col.adjLabel then pcall(col.adjLabel.setStyleSheet, col.adjLabel, frame) end
        end
    end
    css(S.topLabel, "statusbar")
    css(S.leftBg, "window"); css(S.rightBg, "window")
    for _, slot in ipairs(SLOTS) do css(S.panels[slot], "panel") end
    if S.restyle then S.restyle = nil; L.apply() end
end

local function resize()
    if not S.env then return end -- the handler outlived teardown (killEvent failed)
    if S.timer then pcall(S.env.killTimer, S.timer) end
    -- Mudlet raises sysWindowResizeEvent for every setBorder call, so applying on an unchanged
    -- size would loop forever (live: 5 events per second)
    local ok, id = pcall(S.env.timer, 0.2, function()
        S.timer = nil
        local okS, w, h = pcall(S.env.windowSize)
        if okS and w == S.W and h == S.H then return end
        L.apply()
    end)
    S.timer = ok and id or nil
end

function L.removeObjects()
    for i = #(S.objs or {}), 1, -1 do
        local o = S.objs[i]
        pcall(o.hide, o)
        pcall(o.delete, o)
        S.objs[i] = nil
    end
end

function L.teardown()
    local env = S.env
    if not env then return end
    if S.handler then pcall(env.killEvent, S.handler) end
    if S.timer then pcall(env.killTimer, S.timer) end
    pcall(rmgui.theme.unregister, "layout.bars")
    L.removeObjects()
    if S.old then
        pcall(setBorders, S.old.Top, S.old.Right, S.old.Bottom, S.old.Left)
    end
    wipe()
end

function L.init(env)
    if S.env then L.teardown() end
    if type(env) ~= "table" then return end
    S.env, S.objs = env, {}
    local okT, theme = pcall(rmgui.theme.resolve, type(env.settings) == "table" and env.settings.theme or nil)
    S.scale = okT and type(theme) == "table" and theme.imageScale or 1
    S.old = {}
    for _, side in ipairs(SIDES) do
        local ok, v = pcall(_G["getBorder" .. side])
        S.old[side] = ok and v or 0
    end
    local ok, err = pcall(build)
    if not ok then
        say("layout objects failed: " .. tostring(err), "err")
        S.built = false
        L.removeObjects() -- no half-built frame stays on screen
    end
    pcall(rmgui.theme.register, "layout.bars", theming)
    local okE, id = pcall(env.registerEvent, "sysWindowResizeEvent", resize)
    S.handler = okE and id or nil
    L.apply()
end

rmgui.core.register("layout", { init = L.init, teardown = L.teardown })
