-- maphost/glue: puts the map in the "map" layout slot.
-- Preferred: adopt the container the mapper owns (rmap.api.container()). Fallback: our own Geyser.Mapper.
-- shortcut: the fallback mapper and placeholder are ours only until the mapper creates rmap.map; remove them then.
rmgui = rmgui or {}
rmgui.maphost = rmgui.maphost or {}

local M = rmgui.maphost
-- the editor re-runs this file while the old instance is live: stop it (its locals are unreachable later), restart below
local prevEnv = M.env_
if M.teardown then pcall(M.teardown) end
local MAPPER, HOLDER = "rmgui.maphost.mapper", "rmgui.maphost.placeholder"
local EVENTS = { "rmgui.onLayout", "rmap.onRoom", "rmap.onMoved" }

local env, ids, ctx, adopted, mapper, holder

local function reset() env, ids, ctx, adopted, mapper, holder = nil, {}, nil, nil, nil, nil end
reset()

local function del(o) if o then pcall(o.delete, o) end end

local function drawHolder()
    if not holder then return end
    local text = "no map yet - type rmap start"
    pcall(function()
        if not ctx then holder:echo(text) return end -- before the first theme apply
        holder:setStyleSheet(ctx.css("panel"))
        holder:echo(text, ctx.textColor("tab"))
    end)
end

local function slotOf()
    local ok, s = pcall(function() return rmgui.layout.get("map") end)
    return ok and s or nil
end

local function tryAdopt(slot)
    local ok, name = pcall(function() return rmap.api.container() end)
    if not ok or type(name) ~= "string" then return false end
    local ok2, obj = pcall(function() return Geyser.windowList[name] end)
    if not ok2 or type(obj) ~= "table" then return false end
    local ok3 = pcall(function()
        obj:changeContainer(slot)
        obj:resize("100%", "100%")
        obj:move(0, 0)
    end)
    if ok3 then adopted = obj end
    return ok3
end

local function hasMap()
    if type(env.hasMap) ~= "function" then return true end
    local ok, v = pcall(env.hasMap)
    return not ok or v ~= false
end

-- A restyle or a new layout can leave a panel label above the map widget, and then the map draws nothing and takes
-- no clicks (seen live). The widget is raised again each time.
local function raiseMap()
    local w = adopted or mapper
    if w then pcall(w.raise, w) end
end

local function refresh()
    if adopted then raiseMap() return end
    local slot = slotOf()
    if not slot then return end
    if tryAdopt(slot) then
        del(mapper); del(holder); mapper, holder = nil, nil
        raiseMap()
        return
    end
    if mapper then raiseMap() return end
    if hasMap() then
        del(holder); holder = nil
        local ok, m = pcall(function()
            return Geyser.Mapper:new({ name = MAPPER, x = 0, y = 0, width = "100%", height = "100%" }, slot)
        end)
        if ok then mapper = m; raiseMap() end
    elseif not holder then
        local ok, l = pcall(function()
            return Geyser.Label:new({ name = HOLDER, x = 0, y = 0, width = "100%", height = "100%" }, slot)
        end)
        if ok then holder = l; drawHolder() end
    end
end

function M.init(e)
    M.teardown()
    env = e
    M.env_ = e
    pcall(rmgui.theme.register, "maphost.placeholder", function(c) ctx = c; drawHolder(); raiseMap() end)
    for _, ev in ipairs(EVENTS) do
        local ok, id = pcall(env.registerEvent, ev, function() refresh() end)
        if ok and id then ids[#ids + 1] = id end
    end
    refresh()
end

function M.teardown()
    M.env_ = nil
    if env then for _, id in ipairs(ids) do pcall(env.killEvent, id) end end
    -- give the mapper's container back to the root window; it stays alive
    if adopted then pcall(function() adopted:changeContainer(Geyser) end) end
    del(mapper); del(holder)
    if rmgui.theme and rmgui.theme.unregister then pcall(rmgui.theme.unregister, "maphost.placeholder") end
    reset()
end

if rmgui.core and rmgui.core.register then rmgui.core.register("maphost", M) end
if prevEnv then pcall(M.init, prevEnv) end
