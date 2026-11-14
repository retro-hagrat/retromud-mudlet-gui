-- party/glue: one row per party member (name plus hp, sp, ep bars) in the party panel, fed by pssa output.
rmgui = rmgui or {}
rmgui.party = rmgui.party or {}

local P = rmgui.party
local PREFIX = "rmgui.party."
local KEYS = { "hp", "sp", "ep" }
local ELEMENT = "party.gauges"
local ROW = 100 / 8 -- percent of the panel per row; P.MAX rows

local function rgb(c) return ("rgb(%d, %d, %d)"):format(c[1], c[2], c[3]) end

local function draw()
    local members = P.last or {}
    for i, row in ipairs(P.rows or {}) do
        local m = members[i]
        local widgets = { row.label, row.hp, row.sp, row.ep }
        for _, w in ipairs(widgets) do pcall(m and w.show or w.hide, w) end
        if m then
            if P.textHex then row.label:echo(m.name, P.textHex) else row.label:echo(m.name) end
            for _, k in ipairs(KEYS) do
                row[k]:setValue(math.max(0, math.min(m[k .. "Max"], m[k])), m[k .. "Max"])
                row[k].text:echo(("%d/%d"):format(m[k], m[k .. "Max"]), "black", "c")
            end
        end
    end
end

local function styleAll()
    for _, row in ipairs(P.rows or {}) do
        for _, k in ipairs(KEYS) do
            local s = P.style and P.style[k]
            if s then pcall(row[k].setStyleSheet, row[k], s[1], s[2], s[3]) end
        end
        if P.labelStyle then pcall(row.label.setStyleSheet, row.label, P.labelStyle) end
    end
end

local function destroy()
    for _, row in ipairs(P.rows or {}) do
        for _, w in pairs(row) do pcall(w.delete, w) end
    end
    P.rows, P.container = nil, nil
end

local function build(env)
    if not (rmgui.layout and rmgui.layout.get) then return end
    local ok, c = pcall(rmgui.layout.get, "party")
    if not ok or not c then return end
    if P.rows and P.container == c then return end -- the layout may have been rebuilt
    destroy()
    P.rows, P.container = {}, c
    local made, err = pcall(function()
        for i = 1, P.MAX do
            local y = ((i - 1) * ROW) .. "%"
            local row = {}
            row.label = Geyser.Label:new({ name = PREFIX .. i .. ".name", x = 0, y = y, width = "34%", height = (ROW - 1) .. "%" }, c)
            for j, k in ipairs(KEYS) do
                row[k] = Geyser.Gauge:new({
                    name = PREFIX .. i .. "." .. k, x = (35 + (j - 1) * 22) .. "%", y = y, width = "21%", height = (ROW - 1) .. "%",
                }, c)
            end
            P.rows[i] = row
        end
    end)
    if not made then
        destroy()
        env.say("party gauges failed: " .. tostring(err), "warn")
        return
    end
    styleAll()
    draw()
end

local function onLine(line)
    local done = P.feed(P.parseState, line)
    if not done then return end
    P.last = done -- an empty block (nobody listed) clears the panel
    pcall(draw)
end

function P.init(env)
    P.teardown(env)
    P.parseState = {}
    local okT, errT = pcall(rmgui.theme.register, ELEMENT, function(ctx)
        local c = ctx.theme.colors
        P.textHex = ctx.textColor("panel")
        P.labelStyle = ("QLabel{background-color: transparent; color: %s; font-size: %dpt;}"):format(
            P.textHex, (ctx.theme.fonts and ctx.theme.fonts.size) or 10)
        P.style = {}
        for _, k in ipairs(KEYS) do
            P.style[k] = {
                ("background-color: %s; border-radius: 2px;"):format(rgb(c[k])),
                ("background-color: %s; border-radius: 2px;"):format(rgb(c.surface)),
                "color: black;",
            }
        end
        styleAll()
        pcall(draw)
    end)
    if not okT then pcall(env.say, "party theme failed: " .. tostring(errT), "warn") end
    local okL, idL = pcall(env.lineTrigger, onLine)
    if okL then P.trigger = idL else pcall(env.say, "party trigger failed: " .. tostring(idL), "warn") end
    local okH, idH = pcall(env.registerEvent, "rmgui.onLayout", function() build(env) end)
    if okH then P.handler = idH else pcall(env.say, "party layout handler failed: " .. tostring(idH), "warn") end
    build(env)
end

function P.teardown(env)
    if P.trigger then pcall(env.killTrigger, P.trigger) end
    if P.handler then pcall(env.killEvent, P.handler) end
    P.trigger, P.handler = nil, nil
    destroy()
    pcall(rmgui.theme.unregister, ELEMENT)
    P.last, P.style, P.textHex, P.labelStyle, P.parseState = nil, nil, nil, nil, nil
end

rmgui.core.register("party", { init = P.init, teardown = P.teardown })
