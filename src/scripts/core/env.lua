-- core/env: the one place that touches Mudlet globals for the glue modules (rmgui.core.makeEnv).
-- Mudlet functions are looked up when called, so the fake harness (test/fake_mudlet.lua) can stand in.
-- env.settings and env.saveSettings are NOT set here: the boot step fills them after loading settings.
rmgui = rmgui or {}
rmgui.core = rmgui.core or {}

local COLORS = { err = "red", warn = "yellow", ok = "green", info = "grey" }

function rmgui.core.makeEnv()
    local env = {}
    local home = getMudletHomeDir()
    env.homeDir = home
    env.dirs = { player = home .. "/retromud-gui-theme", themes = home .. "/retromud-gui/themes" }

    function env.say(message, level)
        cecho(("<%s>[rmgui] %s\n"):format(COLORS[level] or COLORS.info, tostring(message)))
    end

    function env.exists(path)
        local f = io.open(path, "r")
        if f then f:close() end
        return f ~= nil
    end

    -- table.load raises on a missing or broken file in Mudlet 5.1
    function env.load(path)
        local t = {}
        local ok, err = pcall(table.load, path, t)
        if not ok then return nil, err end
        return t
    end

    function env.save(path, tbl) return table.save(path, tbl) end

    env.mapColors = {
        get = function()
            local r, g, b, a = getMapBackgroundColor()
            local er, eg, eb = getMapRoomExitsColor()
            return { r, g, b, a }, { er, eg, eb }
        end,
        set = function(bg, exits)
            setMapBackgroundColor(bg[1], bg[2], bg[3])
            setMapRoomExitsColor(exits[1], exits[2], exits[3])
        end,
    }
    env.cmdline = { set = function(css) setCmdLineStyleSheet("main", css) end }
    function env.setBorderColor(...) return setBorderColor(...) end

    -- The file runs in an empty environment, so it can only return a table.
    function env.loadOverride()
        local path = env.dirs.player .. "/theme.lua"
        if not env.exists(path) then return nil end
        local fn, err = loadfile(path, "t", {})
        if fn and setfenv then setfenv(fn, {}) end -- Mudlet is Lua 5.1: loadfile ignores the env argument
        local ok, res = false, err
        if fn then ok, res = pcall(fn) end
        if ok and type(res) == "table" then return res end
        env.say("theme override " .. path .. " is broken: " .. tostring(ok and "it must return a table" or res), "err")
        return nil
    end

    function env.timer(seconds, fn) return tempTimer(seconds, fn) end
    function env.killTimer(id) return killTimer(id) end
    function env.windowSize() return getMainWindowSize() end
    function env.charWidth()
        local w = calcFontSize("main")
        return type(w) == "number" and w or 8
    end
    function env.packageVersion(name)
        local v = getPackageInfo(name, "version")
        if type(v) == "string" and v ~= "" then return v end
        return nil
    end
    function env.isPrompt() return isPrompt() end
    function env.currentLine() return getCurrentLine() end
    -- pcall inside: one failing callback must not stop the trigger from running on later lines
    function env.lineTrigger(fn)
        return tempRegexTrigger("^", function() pcall(fn, getCurrentLine()) end)
    end
    function env.killTrigger(id) return killTrigger(id) end
    function env.alias(pattern, fn) return tempAlias(pattern, fn) end
    function env.killAlias(id) return killAlias(id) end
    function env.expandAlias(text) return expandAlias(text) end
    function env.registerEvent(event, fn) return registerAnonymousEventHandler(event, fn) end
    function env.killEvent(id) return killAnonymousEventHandler(id) end
    function env.clearGlobal(name) _G[name] = nil end
    function env.raise(event, ...) return raiseEvent(event, ...) end
    return env
end
