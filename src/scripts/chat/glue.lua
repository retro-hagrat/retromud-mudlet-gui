-- chat/glue: the chat panel. A tab strip of labels and one MiniConsole per tab inside layout slot "chat".
-- Lines are copied from the game window (coloured) into the consoles. See doc/spec/chat.md.
rmgui = rmgui or {}
rmgui.chat = rmgui.chat or {}
local C = rmgui.chat

local NAME = "rmgui.chat"
local STRIP_PX = 40 -- height of the tab strip: the same as a button, and the tab art is the button art

-- shortcut: fixed font size, the env has no way to read the main window font. Upgrade when env gets one.
local FONT = 12

-- state lives on C so that a re-run of this file (the player saves it in the editor) still sees and tears down the old objects
C.state = C.state or {}
local S = C.state

-- The strip height in percent of the slot, so it follows a resize of the slot.
-- shortcut: Geyser has no "100% minus 32 px" size, so the percent is recalculated on each layout event.
local function stripPct()
    local ok, h = pcall(function() return S.slot:get_height() end)
    if not ok or type(h) ~= "number" or h <= 0 then return 7 end
    return math.min(30, math.max(2, STRIP_PX * 100 / h))
end

local function refit() -- the slot may have a new size after a layout change
    if not S.built or not S.strip then return end
    local pct = stripPct()
    pcall(S.strip.resize, S.strip, "100%", pct .. "%")
    for _, c in pairs(S.consoles or {}) do
        pcall(c.move, c, 0, pct .. "%")
        pcall(c.resize, c, "100%", (100 - pct) .. "%")
    end
end

local function reset(new)
    for k in pairs(S) do S[k] = nil end
    for k, v in pairs(new or {}) do S[k] = v end
end

local function say(msg, level)
    if S.env and type(S.env.say) == "function" then pcall(S.env.say, msg, level) end
end

local function tabDef(id)
    for _, t in ipairs(C.TABS) do if t.id == id then return t end end
end

local function title(id)
    local n = S.unread[id] or 0
    local t = tabDef(id).title
    return n > 0 and ("%s %d"):format(t, n) or t -- no brackets: a tab has about 50 px for its text
end

-- A tab is an image label with a transparent text label over its whole area. The image has 12 px
-- borders, which left only about 27 px for the text and cut the names (seen in a live Mudlet).
local function drawTab(id)
    local label, txt = S.tabs[id], S.tabText and S.tabText[id]
    if not label then return end
    local role = id == S.active and "tabActive" or "tab"
    if S.ctx then pcall(label.setStyleSheet, label, S.ctx.css(role)) end
    local target = txt or label
    if txt and S.ctx then
        local size = tonumber(S.ctx.theme and S.ctx.theme.fonts and S.ctx.theme.fonts.sizeSmall) or 9
        pcall(txt.setStyleSheet, txt, ("QLabel{background-color: transparent; color: %s; font-size: %dpt;}"):format(S.ctx.textColor(role), size))
    end
    pcall(target.echo, target, title(id), S.ctx and S.ctx.textColor(role) or nil)
end

local function layoutTabs()
    local n = #S.order
    for i, id in ipairs(S.order) do
        local l = S.tabs[id]
        pcall(l.move, l, ("%.4f%%"):format((i - 1) * 100 / n), 0)
        pcall(l.resize, l, ("%.4f%%"):format(100 / n), "100%")
    end
end

local function paintConsole(c)
    local s = S.ctx and S.ctx.theme.colors.surface
    if s then pcall(c.setColor, c, s[1], s[2], s[3]) end
end

local function activate(id)
    if not S.tabs[id] then return end
    S.active = id
    S.unread[id] = 0
    for tid, c in pairs(S.consoles) do
        if tid == id then c:show() else c:hide() end
    end
    for tid in pairs(S.tabs) do drawTab(tid) end
end

local function addTab(id)
    local def = tabDef(id)
    local label = Geyser.Label:new({ name = NAME .. ".tab." .. id, x = 0, y = 0, width = "10%", height = "100%" }, S.strip)
    S.objs[#S.objs + 1] = label
    S.tabs[id] = label
    S.tabText = S.tabText or {}
    local txt = Geyser.Label:new({ name = NAME .. ".tab." .. id .. ".text", x = 0, y = 0, width = "100%", height = "100%" }, label)
    S.objs[#S.objs + 1] = txt
    S.tabText[id] = txt
    pcall(txt.setClickCallback, txt, function() pcall(activate, id) end)
    S.order[#S.order + 1] = id
    label:setClickCallback(function() pcall(activate, id) end)
    local pct = stripPct()
    local c = Geyser.MiniConsole:new({ name = NAME .. ".console." .. id, x = 0, y = pct .. "%",
        width = "100%", height = (100 - pct) .. "%" }, S.slot)
    S.objs[#S.objs + 1] = c
    S.consoles[id] = c
    pcall(c.setFontSize, c, FONT)
    pcall(c.enableAutoWrap, c)
    local max = S.env.settings and S.env.settings.chat and S.env.settings.chat.maxLines
    if type(max) ~= "number" or max < 1 or max ~= math.floor(max) or max > 1000000 then max = 2000 end -- Lua 5.1: no math.tointeger
    -- shortcut: batch size 1 is a guess for the real call, check in a live profile
    pcall(c.setBufferSize, c, max, 1)
    paintConsole(c)
    c:hide()
    S.unread[id] = 0
    layoutTabs()
    drawTab(id)
    if def.id == S.active then c:show() end
end

local function destroyObjects()
    for i = #S.objs, 1, -1 do pcall(S.objs[i].delete, S.objs[i]) end
    S.objs, S.tabs, S.tabText, S.consoles, S.order, S.unread = {}, {}, {}, {}, {}, {}
    S.strip, S.built = nil, false
end

local function build()
    if S.built or not S.env then return end
    local ok, slot = pcall(function() return rmgui.layout and rmgui.layout.get("chat") end)
    if not ok or not slot then return end
    S.slot = slot
    S.built = true
    local ok2, err = pcall(function()
        S.strip = Geyser.Container:new({ name = NAME .. ".strip", x = 0, y = 0, width = "100%", height = stripPct() .. "%" }, slot)
        S.objs[#S.objs + 1] = S.strip
        for _, t in ipairs(C.TABS) do if not t.lazy then addTab(t.id) end end
        activate("all")
    end)
    if not ok2 then
        say("chat panel failed: " .. tostring(err), "err")
        destroyObjects()
    end
end

local function keep(group)
    local km = S.env.settings and S.env.settings.chat and S.env.settings.chat.keepInMain
    return not (type(km) == "table" and km[group] == false)
end

-- append the current coloured game line to the tabs of msg
local function route(msg, first)
    if not S.built then return end
    local tabs = C.tabsFor(msg)
    for _, id in ipairs(tabs) do
        if id == "wizard" and not S.tabs.wizard then pcall(addTab, "wizard") end
    end
    pcall(selectCurrentLine)
    pcall(copy)
    for _, id in ipairs(tabs) do
        local c = S.consoles[id]
        if c then
            if first then
                local p = C.prefixFor(msg, id)
                if p ~= "" then pcall(c.echo, c, p) end
            end
            pcall(appendBuffer, NAME .. ".console." .. id)
            if id ~= S.active then
                S.unread[id] = S.unread[id] + 1
                drawTab(id)
            end
        end
    end
    if not keep(msg.group) then pcall(deleteLine) end
end

local function onLine(line)
    local e = S.engine
    if not e then return end
    local done = e:feed(line, S.env.isPrompt())
    local p = e.pending
    if p and p ~= S.cur then
        S.cur, S.seen = p, #p.lines
        route(p, true)
    elseif p and #p.lines > S.seen then
        S.seen = #p.lines
        route(p, false)
    elseif not p then
        S.cur = nil
    end
    if done then S.env.raise("rmgui.onChat", done.channel, done.group, done.speaker, done.rank, done.text) end
end

local function applyTheme(ctx)
    S.ctx = ctx
    for id in pairs(S.tabs) do drawTab(id) end
    for _, c in pairs(S.consoles) do paintConsole(c) end
end

local function teardown(env)
    env = env or S.env
    if env then
        if S.trigger then pcall(env.killTrigger, S.trigger) end
        if S.handler then pcall(env.killEvent, S.handler) end
    end
    if rmgui.theme and rmgui.theme.unregister then pcall(rmgui.theme.unregister, "chat.tabs") end
    if S.objs then destroyObjects() end
    reset()
end

local function init(env)
    teardown(env) -- a second init must not leave duplicates
    reset({ env = env, objs = {}, tabs = {}, consoles = {}, order = {}, unread = {}, active = "all" })
    local ok, err = pcall(function()
        S.engine = C.newEngine()
        rmgui.theme.register("chat.tabs", applyTheme)
        S.handler = env.registerEvent("rmgui.onLayout", function() build(); refit() end)
        build()
        S.trigger = env.lineTrigger(onLine)
    end)
    if not ok then say("chat failed to start: " .. tostring(err), "err") end
end

C.glue = { init = init, teardown = teardown }
rmgui.core.register("chat", C.glue)
