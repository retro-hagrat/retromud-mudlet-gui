-- boot/start: wires env, settings, the rgui aliases and the theme step, then starts the modules.
rmgui = rmgui or {}
rmgui.boot = rmgui.boot or {}

local env = rmgui.core.makeEnv()
local settings, problems = rmgui.settings.load(env)
for _, p in ipairs(problems or {}) do env.say(p, "warn") end
env.settings = settings
function env.saveSettings()
    local ok, err = rmgui.settings.save(env, env.settings)
    if not ok then env.say("cannot save settings: " .. tostring(err), "err") end
    return ok
end
rmgui.boot.env = env

local aliasIds = {}

local function killAliases()
    for _, id in ipairs(aliasIds) do pcall(env.killAlias, id) end
    aliasIds = {}
end

-- ok, wantSave from command; a failing command must not raise into the alias
local function run(fn, args)
    local ok, res, save = pcall(fn, args, env, env.settings)
    if not ok then env.say("command failed: " .. tostring(res), "err")
    elseif save then env.saveSettings() end
end

-- registered last: runs after every module built its elements, stops first
rmgui.core.register("boot", {
    init = function()
        killAliases()
        aliasIds[1] = env.alias("^rgui theme(.*)$", function() run(rmgui.theme.command, matches[2]) end)
        aliasIds[2] = env.alias("^rgui layout(.*)$", function() run(rmgui.layout.command, matches[2]) end)
        rmgui.theme.apply(env.settings.theme, env, env.settings)
    end,
    teardown = function()
        killAliases()
        rmgui.theme.restore(env)
    end,
})

rmgui.core.install(env, "retromud-gui")
-- start is idempotent, so a later sysLoadEvent does nothing
rmgui.core.start(env)
