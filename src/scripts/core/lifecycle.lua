rmgui = rmgui or {}
rmgui.core = rmgui.core or {}

local core = rmgui.core
local mods, byName = {}, {}   -- registration order; name -> entry
local started, ran, failed = false, {}, {}
local ids = {}

local function report(env, msg)
    if type(env.say) == "function" then pcall(env.say, msg, "err") end
end

local function tableEnv(env) return type(env) == "table" and env or {} end

-- a hostile mod table (erroring __index) must not break start or stop
local function field(mod, key)
    local ok, v = pcall(function() return mod[key] end)
    return ok and v or nil
end

function core.register(name, mod)
    if type(name) ~= "string" or name == "" or type(mod) ~= "table" then return false end
    if byName[name] then
        byName[name].mod = mod
    else
        local e = { name = name, mod = mod }
        mods[#mods + 1] = e
        byName[name] = e
    end
    return true
end

function core.start(env)
    if started then return false end
    env = tableEnv(env)
    started, ran, failed = true, {}, {}
    for _, e in ipairs(mods) do
        local init = field(e.mod, "init")
        local ok, err = true, nil
        if type(init) == "function" then ok, err = pcall(init, env) end
        if ok then
            ran[#ran + 1] = e
        else
            failed[#failed + 1] = e.name
            report(env, ("module %s failed to start: %s"):format(e.name, tostring(err)))
        end
    end
    return true
end

function core.stop(env)
    if not started then return false end
    env = tableEnv(env)
    local list = ran
    ran = {} -- a teardown that calls stop must not run the list twice
    for i = #list, 1, -1 do
        local e = list[i]
        local td = field(e.mod, "teardown")
        if type(td) == "function" then
            local ok, err = pcall(td, env)
            if not ok then report(env, ("module %s failed to stop: %s"):format(e.name, tostring(err))) end
        end
    end
    started, ran, failed = false, {}, {}
    return true
end

function core.state()
    local order, f = {}, {}
    for i, e in ipairs(mods) do order[i] = e.name end
    for i, n in ipairs(failed) do f[i] = n end
    return { started = started, order = order, failed = f }
end

function core.uninstall(env)
    env = tableEnv(env)
    if type(env.killEvent) ~= "function" then return false end
    for _, id in ipairs(ids) do pcall(env.killEvent, id) end
    ids = {}
    return true
end

function core.install(env, pkgName)
    env = tableEnv(env)
    if type(pkgName) ~= "string" or pkgName == "" then return false end
    if type(env.registerEvent) ~= "function" or type(env.killEvent) ~= "function" then return false end
    core.uninstall(env)
    local function add(event, fn)
        local ok, id = pcall(env.registerEvent, event, fn)
        if ok then ids[#ids + 1] = id end
    end
    add("sysLoadEvent", function() core.start(env) end)
    add("sysInstallPackage", function(_, pkg)
        if pkg == pkgName then core.start(env) end
    end)
    add("sysUninstallPackage", function(_, pkg)
        if pkg ~= pkgName then return end
        core.stop(env)
        core.uninstall(env)
        if type(env.clearGlobal) == "function" then pcall(env.clearGlobal, "rmgui") end
    end)
    return true
end
