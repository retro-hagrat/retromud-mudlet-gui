rmgui = rmgui or {}
rmgui.settings = rmgui.settings or {}
local S = rmgui.settings

function S.defaults()
    return {
        version = 1,
        theme = "perdow",
        mapTheming = true,
        cmdlineTheming = false,
        layout = { mode = "auto" },
        ui = { hintShown = false },
        custom = {}, -- the player's buttons, see custom/logic.lua; each entry is checked there
        chat = {
            maxLines = 2000,
            -- true because the spec has not decided yet (CHAT-040, open question 8)
            keepInMain = { chat = true, world = true, wizard = true, info = true, alert = true, guild = true, party = true, tells = true },
        },
    }
end

local function isNum(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end
local function positive(v) return isNum(v) and v > 0 end

local MODES = { auto = true, wide = true, compact = true }
local checks = {
    theme = { function(v) return type(v) == "string" and v ~= "" end, "a non-empty string" },
    mapTheming = { function(v) return type(v) == "boolean" end, "a boolean" },
    cmdlineTheming = { function(v) return type(v) == "boolean" end, "a boolean" },
    mode = { function(v) return MODES[v] == true end, "auto, wide or compact" },
    chatWidth = { positive, "a number above 0" },
    sideWidth = { positive, "a number above 0" },
    topHeight = { positive, "a number above 0" },
    maxLines = { function(v) return isNum(v) and v % 1 == 0 and v >= 100 and v <= 20000 end, "an integer from 100 to 20000" },
    hintShown = { function(v) return type(v) == "boolean" end, "a boolean" },
    keep = { function(v) return type(v) == "boolean" end, "a boolean" },
}

local function sortedKeys(t)
    local ks = {}
    for k in pairs(t) do ks[#ks + 1] = k end
    table.sort(ks, function(a, b) return tostring(a) < tostring(b) end)
    return ks
end

-- Copy valid keys of src into dst. dst holds the known keys (or `allowed` lists them).
-- rules maps a key to a check name. path is the dotted prefix for problem texts.
local function overlay(src, dst, rules, path, problems)
    for _, k in ipairs(sortedKeys(src)) do
        local v, full = src[k], path .. tostring(k)
        local rule = type(k) == "string" and rules[k]
        if not rule then
            problems[#problems + 1] = "unknown setting " .. full
        else
            local c = checks[rule]
            if c[1](v) then
                dst[k] = v
            else
                problems[#problems + 1] = full .. " must be " .. c[2]
            end
        end
    end
end

local function section(saved, key, fn, problems, path)
    local v = saved[key]
    if v == nil then return end
    if type(v) ~= "table" then
        problems[#problems + 1] = (path or "") .. key .. " must be a table"
        return
    end
    fn(v)
end

local function mergeRaw(saved)
    local out, problems = S.defaults(), {}
    if type(saved) ~= "table" then
        problems[1] = "settings must be a table"
        return out, problems
    end
    local top = { theme = "theme", mapTheming = "mapTheming", cmdlineTheming = "cmdlineTheming" }
    local flat = {}
    for k, v in pairs(saved) do
        if k ~= "layout" and k ~= "chat" and k ~= "ui" and k ~= "custom" and k ~= "version" then flat[k] = v end
    end
    overlay(flat, out, top, "", problems)
    section(saved, "layout", function(t)
        overlay(t, out.layout, { mode = "mode", chatWidth = "chatWidth", sideWidth = "sideWidth", topHeight = "topHeight" }, "layout.", problems)
    end, problems)
    section(saved, "ui", function(t)
        overlay(t, out.ui, { hintShown = "hintShown" }, "ui.", problems)
    end, problems)
    section(saved, "custom", function(t) out.custom = t end, problems)
    section(saved, "chat", function(t)
        local rest = {}
        for k, v in pairs(t) do if k ~= "keepInMain" then rest[k] = v end end
        overlay(rest, out.chat, { maxLines = "maxLines" }, "chat.", problems)
        section(t, "keepInMain", function(km)
            local rules = {}
            for k in pairs(out.chat.keepInMain) do rules[k] = "keep" end
            overlay(km, out.chat.keepInMain, rules, "chat.keepInMain.", problems)
        end, problems, "chat.")
    end, problems)
    -- Mudlet runs Lua 5.1: no math.tointeger there, and a float prints as 500 anyway
    if math.tointeger then out.chat.maxLines = math.tointeger(out.chat.maxLines) or out.chat.maxLines end
    return out, problems
end

-- a hostile saved table (raising metatable) must not raise
function S.merge(saved)
    local ok, out, problems = pcall(mergeRaw, saved)
    if ok then return out, problems end
    return S.defaults(), { "settings cannot be read: " .. tostring(out) }
end

function S.path(homeDir)
    if type(homeDir) ~= "string" then return nil end
    return ((homeDir .. "/retromud-gui-settings.lua"):gsub("\\", "/"))
end

function S.load(env)
    local p = type(env) == "table" and S.path(env.homeDir)
    if not p then
        local d = S.defaults()
        return d, { "env.homeDir must be a string" }
    end
    local ok, there = pcall(env.exists, p)
    if ok and not there then return S.defaults(), {} end
    if not ok then return S.defaults(), { "cannot check settings file: " .. tostring(there) } end
    local ok2, tbl, err = pcall(env.load, p)
    if not ok2 then return S.defaults(), { "cannot read settings file: " .. tostring(tbl) } end
    if type(tbl) ~= "table" then
        return S.defaults(), { "cannot read settings file: " .. tostring(err or "not a table") }
    end
    return S.merge(tbl)
end

function S.save(env, settings)
    local p = type(env) == "table" and S.path(env.homeDir)
    if not p then return nil, "env.homeDir must be a string" end
    if type(settings) ~= "table" then return nil, "settings must be a table" end
    local clean = S.merge(settings)
    local ok, res, err = pcall(env.save, p, clean)
    if not ok then return nil, tostring(res) end
    if res then return true end
    return nil, tostring(err or "save failed")
end
