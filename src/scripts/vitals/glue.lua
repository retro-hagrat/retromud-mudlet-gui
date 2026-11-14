-- vitals/glue: three gauges (hp, sp, ep) in the vitals panel, fed by the prompt line.
rmgui = rmgui or {}
rmgui.vitals = rmgui.vitals or {}

local V = rmgui.vitals
local PREFIX = "rmgui.vitals."
local KEYS = { { "hp", "HP" }, { "sp", "SP" }, { "ep", "EP" } }
local ELEMENT = "vitals.gauges"

local function rgb(c) return ("rgb(%d, %d, %d)"):format(c[1], c[2], c[3]) end

-- The numbers sit in their own label at the left of the bar, on the panel background. Text drawn on
-- the bar itself is unreadable: one colour cannot contrast with both a bright bar and a dark back
-- (seen in a live Mudlet on the bright sosel colours).
local function draw(g, key, label, d)
    local cur, max = d[key], d[key .. "Max"]
    local bar = math.max(0, math.min(max, cur))
    g:setValue(bar, max)
    local l = V.labels and V.labels[key]
    if l then
        local text = ("%s %d/%d"):format(label, cur, max)
        if V.textHex then l:echo(text, V.textHex) else l:echo(text) end
    end
end

local function drawAll()
    if not V.last then return end
    for _, k in ipairs(KEYS) do
        local g = V.gauges and V.gauges[k[1]]
        if g then pcall(draw, g, k[1], k[2], V.last) end
    end
end

local function styleAll()
    if not V.gauges or not V.style then return end
    for _, k in ipairs(KEYS) do
        local g, s = V.gauges[k[1]], V.style[k[1]]
        if g and s then pcall(g.setStyleSheet, g, s[1], s[2], s[3]) end
        local l = V.labels and V.labels[k[1]]
        if l and V.labelStyle then pcall(l.setStyleSheet, l, V.labelStyle) end
    end
end

local function destroy()
    for _, g in pairs(V.gauges or {}) do pcall(g.delete, g) end
    for _, l in pairs(V.labels or {}) do pcall(l.delete, l) end
    V.gauges, V.labels, V.container = nil, nil, nil
end

local function build(env)
    if not (rmgui.layout and rmgui.layout.get) then return end
    local ok, c = pcall(rmgui.layout.get, "vitals")
    if not ok or not c then return end
    -- the layout may have been rebuilt: gauges of a replaced slot died with it
    if V.gauges and V.container == c then return end
    destroy()
    V.gauges, V.labels, V.container = {}, {}, c
    local made, err = pcall(function()
        for i, k in ipairs(KEYS) do
            -- 32% + 2% gap per row; percentages follow container resizes, unlike fixed pixels
            local y = ((i - 1) * 34) .. "%"
            V.labels[k[1]] = Geyser.Label:new({
                name = PREFIX .. k[1] .. "label", x = 0, y = y, width = "36%", height = "32%",
            }, c)
            V.gauges[k[1]] = Geyser.Gauge:new({
                name = PREFIX .. k[1], x = "38%", y = y, width = "62%", height = "32%",
            }, c)
        end
    end)
    if not made then
        destroy()
        env.say("vitals gauges failed: " .. tostring(err), "warn")
        return
    end
    styleAll()
    drawAll()
end

local function onLine(env, line)
    if not V.isPromptLine(line) then return end
    local new = V.parse(line)
    if not new or not V.changed(V.last, new) then return end
    V.last = new
    drawAll()
    env.raise("rmgui.onVitals", new)
end

function V.init(env)
    V.teardown(env)
    -- shortcut: gauge colours are plain stylesheets, no image roles; upgrade when the themes ship gauge images
    local okT, errT = pcall(rmgui.theme.register, ELEMENT, function(ctx)
        local c = ctx.theme.colors
        V.textHex = ctx.textColor("panel")
        V.labelStyle = ("QLabel{background-color: transparent; color: %s; font-size: %dpt;}"):format(
            V.textHex, (ctx.theme.fonts and ctx.theme.fonts.size) or 10)
        V.style = {}
        for _, k in ipairs(KEYS) do
            V.style[k[1]] = {
                ("background-color: %s; border-radius: 2px;"):format(rgb(c[k[1]])),
                ("background-color: %s; border-radius: 2px;"):format(rgb(c.surface)),
                ("color: %s;"):format(rgb(c.text)),
            }
        end
        styleAll()
        drawAll()
    end)
    if not okT then pcall(env.say, "vitals theme failed: " .. tostring(errT), "warn") end
    local okL, idL = pcall(env.lineTrigger, function(line) onLine(env, line) end)
    if okL then V.trigger = idL else pcall(env.say, "vitals trigger failed: " .. tostring(idL), "warn") end
    local okH, idH = pcall(env.registerEvent, "rmgui.onLayout", function() build(env) end)
    if okH then V.handler = idH else pcall(env.say, "vitals layout handler failed: " .. tostring(idH), "warn") end
    build(env)
end

function V.teardown(env)
    if V.trigger then pcall(env.killTrigger, V.trigger) end
    if V.handler then pcall(env.killEvent, V.handler) end
    V.trigger, V.handler = nil, nil
    destroy()
    pcall(rmgui.theme.unregister, ELEMENT)
    V.last, V.style, V.textHex, V.labelStyle = nil, nil, nil, nil
end

rmgui.core.register("vitals", { init = V.init, teardown = V.teardown })
