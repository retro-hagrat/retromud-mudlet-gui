-- buttons/glue: a 2 by 2 grid of mapper buttons in the "buttons" layout slot.
-- Calls rmap.api when it exists, else the "rmap ..." aliases. Talks to Mudlet only through env.
rmgui = rmgui or {}
rmgui.buttons = rmgui.buttons or {}

local B = rmgui.buttons
-- the editor re-runs this file while the old instance is live: stop it (its locals are unreachable later), restart below
local prevEnv = B.env_
if B.teardown then pcall(B.teardown) end
local PREFIX = "rmgui.buttons."
-- the toggle names the action a click will do: "start map" while off, "stop map" while on
local ORDER = { "where", "scan", "undo", "mapToggle" }
local CELL = { where = 0, scan = 25, undo = 50, mapToggle = 75 } -- one row, a quarter each

local env, labels, texts, ids, ctx, mapping, built

local function reset()
    env, labels, texts, ids, ctx, mapping, built = nil, {}, {}, {}, nil, false, false
end
reset()

local function say(msg, level)
    if env and type(env.say) == "function" then pcall(env.say, msg, level) end
end

local function api()
    local ok, a = pcall(function() return rmap and rmap.api end)
    if ok and type(a) == "table" then return a end
    return nil
end

local function missing()
    local ok, v = pcall(env.packageVersion, "retromud")
    return not ok or v == nil
end

local function draw(name)
    local l = labels[name]
    if not l then return end
    pcall(function()
        if not ctx then l:echo(texts[name]) return end -- before the first theme apply
        l:setStyleSheet(ctx.css("button"))
        l:echo(texts[name], ctx.textColor(missing() and "tab" or "button"))
    end)
end

local function drawAll() for _, n in ipairs(ORDER) do draw(n) end end

local function setText(name, text)
    texts[name] = text
    draw(name)
end

-- run an api function; report a nil + reason result or an error
local function callApi(fn)
    local ok, res, reason = pcall(fn)
    if not ok then say("mapper call failed: " .. tostring(res), "err")
    elseif res == nil and reason then say(reason, "warn") end
end

local function act(name)
    if missing() then say("the mapper package is not installed", "warn") return end
    local a = api()
    if name == "mapToggle" then
        local isOn = mapping
        if a and type(a.isMapping) == "function" then
            local ok, v = pcall(a.isMapping)
            if ok then isOn = v and true or false end
        end
        local verb = isOn and "stop" or "start"
        if a and type(a[verb]) == "function" then
            callApi(a[verb])
            local ok2, v2 = pcall(a.isMapping) -- the mapper may not raise rmap.onMapping: read the state back
            if ok2 and type(v2) == "boolean" then mapping = v2; setText("mapToggle", mapping and "stop map" or "start map") end
        else
            pcall(env.expandAlias, "rmap " .. verb)
            mapping = not isOn -- no api: remembered state is all we have
            setText("mapToggle", mapping and "stop map" or "start map")
        end
        return
    end
    if a and type(a[name]) == "function" then callApi(a[name])
    else pcall(env.expandAlias, "rmap " .. name) end
end

local function build()
    if built then return end
    local ok, slot = pcall(function() return rmgui.layout.get("buttons") end)
    if not ok or not slot then return end
    built = true
    for _, n in ipairs(ORDER) do
        local ok2, l = pcall(function()
            return Geyser.Label:new({
                name = PREFIX .. n, x = CELL[n] .. "%", y = 0, width = "25%", height = "100%",
            }, slot)
        end)
        if ok2 and l then
            labels[n] = l
            pcall(l.setClickCallback, l, function() act(n) end)
        end
    end
    local a = api()
    if a and type(a.isMapping) == "function" then
        local ok3, v = pcall(a.isMapping)
        if ok3 then mapping = v and true or false end
    end
    texts.where, texts.scan, texts.undo = "where", "scan", "undo"
    texts.mapToggle = mapping and "stop map" or "start map"
    drawAll()
end

function B.init(e)
    B.teardown()
    env = e
    B.env_ = e
    pcall(rmgui.theme.register, "buttons.labels", function(c) ctx = c; drawAll() end)
    local function on(event, fn)
        local ok, id = pcall(env.registerEvent, event, fn)
        if ok and id then ids[#ids + 1] = id end
    end
    on("rmgui.onLayout", function() build() end)
    on("rmap.onMapping", function(_, on_)
        mapping = on_ and true or false
        if built then setText("mapToggle", mapping and "stop map" or "start map") end
    end)
    build()
end

function B.teardown()
    B.env_ = nil
    if env then
        for _, id in ipairs(ids) do pcall(env.killEvent, id) end
    end
    for _, l in pairs(labels) do pcall(l.delete, l) end
    if rmgui.theme and rmgui.theme.unregister then pcall(rmgui.theme.unregister, "buttons.labels") end
    reset()
end

if rmgui.core and rmgui.core.register then rmgui.core.register("buttons", B) end
if prevEnv then pcall(B.init, prevEnv) end
