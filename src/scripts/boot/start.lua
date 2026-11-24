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

-- same look as "rmap help": a title, then one cyan command and its text per line
local HELP = {
    { "rgui help", "show this text" },
    { "rgui theme", "list the themes and show the active one" },
    { "rgui theme <name>", "switch theme" },
    { "rgui theme reload", "read your theme files again" },
    { "rgui layout <mode>", "wide, compact or auto" },
    { "wt", "list the world transport aliases (wt shaft, ship, key, pod, grove, gate)" },
}
function rmgui.boot.help()
    local lines = { "<cyan>[rmgui]<reset> RetroMUD GUI" }
    for _, c in ipairs(HELP) do lines[#lines + 1] = ("  <cyan>%-20s<reset>%s"):format(c[1], c[2]) end
    env.cecho(table.concat(lines, "\n") .. "\n")
end

-- Mudlet's starter interface draws its own map, chat and vitals over ours: remove it (Package Manager restores it).
local function dropStarterUi()
    if not (getPackages and uninstallPackage) then return end
    for _, pkg in ipairs(getPackages()) do
        if pkg == "mudlet-base-ui" then
            uninstallPackage(pkg)
            env.say("removed Mudlet's starter interface (mudlet-base-ui); it draws its own map, chat and vitals over this GUI", "warn")
        end
    end
end

-- registered last: runs after every module built its elements, stops first
rmgui.core.register("boot", {
    init = function()
        dropStarterUi()
        killAliases()
        aliasIds[1] = env.alias("^rgui theme(.*)$", function() run(rmgui.theme.command, matches[2]) end)
        aliasIds[2] = env.alias("^rgui layout(.*)$", function() run(rmgui.layout.command, matches[2]) end)
        aliasIds[3] = env.alias("^rgui$", function() rmgui.boot.help() end)
        aliasIds[4] = env.alias("^rgui help$", function() rmgui.boot.help() end)
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
