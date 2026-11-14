-- statusbar/glue: the label in the top bar. See doc/design.md (Status bar rules).
rmgui = rmgui or {}
rmgui.statusbar = rmgui.statusbar or {}
local S = rmgui.statusbar

-- the file ran again (saved in the editor): the old chunk's locals are unreachable, so
-- stop its module through the old S.teardown first and restart it with the same env after
local rerun = S.liveEnv
if S.teardown then pcall(S.teardown) end

local LABEL = "rmgui.statusbar.label"
local ELEMENT = "statusbar.label"

local env, label, ctx, state, handlers, said, movedSeen

local function fresh()
    return { roomName = nil, areaName = nil, mapping = false, syncState = nil, mapperInstalled = false }
end

-- say once per distinct message so a broken handler cannot flood the main window
local function report(where, err)
    local msg = where .. ": " .. tostring(err)
    if said[msg] then return end
    said[msg] = true
    if env and env.say then pcall(env.say, msg, "err") end
end

-- The bar behind the label already has the image and its frame. The label only carries the text, so
-- it gets a transparent plain style: giving it the full statusbar stylesheet put the 8 px image
-- borders inside a 20 px bar and left no room for the text (seen in a live Mudlet).
local function textStyle(c)
    local size = type(c.theme) == "table" and type(c.theme.fonts) == "table" and c.theme.fonts.size or 10
    return ("QLabel{background-color: transparent; color: %s; font-size: %dpt;}"):format(c.textColor("statusbar"), size)
end

local function render()
    if not label then return end
    local ok, err = pcall(function()
        local opts = {}
        -- width or char size failing must not stop the text; px 0 means not laid out yet
        local okw, px, cw = pcall(function() return label:get_width(), env.charWidth() end)
        if okw and type(px) == "number" and type(cw) == "number" and px > 0 and cw > 0 then
            opts.maxChars = math.max(1, math.floor(px / cw))
        end
        local text = S.format(state, opts).text
        if ctx then label:echo(text, ctx.textColor("statusbar")) else label:echo(text) end
    end)
    if not ok then report("render", err) end
end

local function build()
    local ok, container = pcall(function() return rmgui.layout and rmgui.layout.get("top") end)
    if not ok or not container then return end
    if label then
        -- the layout redraws on every resize; a rebuilt layout leaves our label in a dead parent
        if label.parent == container then render() return end
        pcall(label.delete, label)
        label = nil
    end
    local made, l = pcall(Geyser.Label.new, Geyser.Label,
        { name = LABEL, x = 0, y = 0, width = "100%", height = "100%" }, container)
    if not made or not l then report("label", l) return end
    label = l
    if ctx then pcall(label.setStyleSheet, label, textStyle(ctx)) end
    render()
end

local function guarded(name, fn)
    return function(_, ...)
        local ok, err = pcall(fn, ...)
        if not ok then report(name, err) end
    end
end

local function on(event, fn)
    local ok, id = pcall(env.registerEvent, event, guarded(event, fn))
    if ok and id then handlers[#handlers + 1] = id end
end

local function recheck()
    state.mapperInstalled = env.packageVersion("retromud") ~= nil
    render()
end

local function seed()
    local api = rmap and rmap.api
    if type(api) ~= "table" then return end
    local ok, st = pcall(api.state)
    if ok and type(st) == "string" then state.syncState = st end
    local okp, id, name, area = pcall(api.position)
    if okp and type(name) == "string" then
        state.roomName, state.areaName, movedSeen = name, area, true
    end
    local okm, m = pcall(api.isMapping)
    if okm then state.mapping = m == true end
end

function S.init(e)
    if env then S.teardown() end
    S.liveEnv = e
    env, state, handlers, said, movedSeen, ctx, label = e, fresh(), {}, {}, false, nil, nil
    pcall(function() state.mapperInstalled = env.packageVersion("retromud") ~= nil end)
    pcall(seed)
    pcall(rmgui.theme.register, ELEMENT, function(c)
        ctx = c
        if label then pcall(label.setStyleSheet, label, textStyle(c)) end
        render()
    end)
    on("rmap.onRoom", function(room)
        if movedSeen or type(room) ~= "table" then return end
        state.roomName = room.name
        render()
    end)
    on("rmap.onMoved", function(_, name, area)
        movedSeen = true
        state.roomName, state.areaName = name, area
        render()
    end)
    on("rmap.onState", function(st) state.syncState = st render() end)
    on("rmap.onMapping", function(m) state.mapping = m == true render() end)
    on("sysInstallPackage", recheck)
    on("sysUninstallPackage", recheck)
    on("rmgui.onLayout", build)
    build()
end

function S.teardown()
    if env then
        for _, id in ipairs(handlers or {}) do pcall(env.killEvent, id) end
    end
    if label then pcall(label.delete, label) end
    pcall(rmgui.theme.unregister, ELEMENT)
    env, label, ctx, state, handlers, said, movedSeen = nil, nil, nil, nil, nil, nil, nil
    S.liveEnv = nil
end

rmgui.core.register("statusbar", { init = S.init, teardown = S.teardown })
if rerun then pcall(S.init, rerun) end
