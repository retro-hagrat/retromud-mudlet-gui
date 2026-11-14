-- theme/apply: apply a theme to the registered elements, the map and the command line.
-- Pure Lua: no Mudlet or Geyser calls. See doc/spec/theming.md section 7.
--
-- env members (all optional except where noted; a missing member skips its step):
--   exists(path) -> bool                 file test for image lookup
--   dirs = { player = s, themes = s }    image folders (THEME-009)
--   loadOverride() -> table|nil          the player's override table
--   say(message, level)                  level is "warn" or "error"; nil means info
--   mapColors = { get() -> bg, exits; set(bg, exits) }
--   setBorderColor(r, g, b)
--   cmdline = { set(css) }
--   raise(eventName, ...)
-- settings = { mapTheming = bool, cmdlineTheming = bool, theme = name }
rmgui = rmgui or {}
rmgui.theme = rmgui.theme or {}
local T = rmgui.theme

T.state = T.state or {}
local elements = {} -- ordered { name =, fn = }

local function say(env, msg, level)
    if env and type(env.say) == "function" then pcall(env.say, msg, level) end
end

local function copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = copy(x) end
    return c
end

function T.register(name, fn)
    if type(fn) ~= "function" then return false end
    for _, e in ipairs(elements) do
        if e.name == name then e.fn = fn return true end
    end
    elements[#elements + 1] = { name = name, fn = fn }
    return true
end

function T.unregister(name)
    for i, e in ipairs(elements) do
        if e.name == name then table.remove(elements, i) return true end
    end
    return false
end

function T.list()
    local out = {}
    for name, p in pairs(T.presets) do out[#out + 1] = { name = name, title = p.title, description = p.description } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function T.active() return T.state.active end

-- %.0f, not %d: an override colour may be fractional or NaN and %d raises on those
local function rgb(c) return ("rgb(%.0f, %.0f, %.0f)"):format(c[1], c[2], c[3]) end

function T.apply(name, env, settings)
    env, settings = type(env) == "table" and env or {}, type(settings) == "table" and settings or {}
    if type(name) ~= "string" or not T.presets[name] then
        say(env, "unknown theme: " .. tostring(name), "error")
        return false
    end
    local report = { problems = 0, warnings = 0, failedElements = {} }

    local override
    if type(env.loadOverride) == "function" then
        local ok, res = pcall(env.loadOverride)
        if ok then override = type(res) == "table" and res or nil
        else
            report.problems = report.problems + 1
            say(env, "theme override file failed to load: " .. tostring(res), "warn")
        end
    end
    local theme, problems = T.resolve(name, override)
    for _, p in ipairs(problems) do
        report.problems = report.problems + 1
        say(env, "theme override: " .. p, "warn")
    end
    for _, w in ipairs(T.contrastProblems(theme)) do
        report.warnings = report.warnings + 1
        say(env, "low contrast, " .. w, "warn")
    end

    local images = {}
    if type(env.exists) == "function" and type(env.dirs) == "table" and env.dirs.player and env.dirs.themes then
        for _, role in ipairs(T.roles) do
            local ok, path = pcall(T.findImage, role, name, env.dirs, env.exists)
            if ok then images[role] = path end
        end
    end
    local ctx = {
        theme = theme, name = name,
        image = function(role) return images[role] end,
        css = function(role) return (T.css(role, theme, images[role])) end,
        textColor = function(role) return (T.textColor(role, theme)) end,
    }
    -- copy of the list: an element may register or unregister while it runs
    local list = {}
    for i, e in ipairs(elements) do list[i] = e end
    for _, e in ipairs(list) do
        local ok, err = pcall(e.fn, ctx)
        if not ok then
            report.failedElements[#report.failedElements + 1] = e.name
            say(env, ("element %s failed: %s"):format(tostring(e.name), tostring(err)), "error")
        end
    end

    local m = env.mapColors
    if settings.mapTheming and type(m) == "table" then
        if T.state.originalMap == nil and type(m.get) == "function" then
            local ok, bg, exits = pcall(m.get)
            if ok and type(bg) == "table" then T.state.originalMap = { bg = copy(bg), exits = copy(exits) } end
        end
        if type(m.set) == "function" then
            local ok, err = pcall(m.set, copy(theme.colors.map.background), copy(theme.colors.map.exits))
            if not ok then say(env, "map colours failed: " .. tostring(err), "error") end
        end
    end
    if settings.mapTheming and type(env.setBorderColor) == "function" then
        local s = theme.colors.surface
        local ok, err = pcall(env.setBorderColor, s[1], s[2], s[3])
        if not ok then say(env, "border colour failed: " .. tostring(err), "error") end
    end
    if settings.cmdlineTheming and type(env.cmdline) == "table" and type(env.cmdline.set) == "function" then
        local c = theme.cmdline
        local ok, err = pcall(env.cmdline.set,
            ("QPlainTextEdit{background-color: %s; color: %s;}"):format(rgb(c.background), rgb(c.text)))
        if not ok then say(env, "command line style failed: " .. tostring(err), "error") end
    end

    T.state.active = name
    if type(env.raise) == "function" then pcall(env.raise, "rmgui.onTheme", name) end
    return true, report
end

function T.restore(env)
    local o = T.state.originalMap
    if o and env and type(env.mapColors) == "table" and type(env.mapColors.set) == "function" then
        local ok, err = pcall(env.mapColors.set, copy(o.bg), copy(o.exits))
        if not ok then say(env, "map colours failed: " .. tostring(err), "error") end
    end
    T.state.active, T.state.originalMap = nil, nil
end

function T.command(argString, env, settings)
    env = type(env) == "table" and env or {}
    local arg = tostring(argString or ""):match("^%s*(.-)%s*$"):lower()
    local function showList()
        for _, t in ipairs(T.list()) do
            say(env, ("  %s - %s: %s"):format(t.name, t.title, t.description))
        end
    end
    if arg == "" then
        say(env, "active theme: " .. tostring(T.state.active or "none"))
        showList()
        return true, false
    elseif arg == "list" then
        showList()
        return true, false
    elseif arg == "reload" then
        if not T.state.active then
            say(env, "no theme is active yet")
            return false, false
        end
        return (T.apply(T.state.active, env, settings)), false
    elseif not T.presets[arg] then
        say(env, ("unknown theme: %s (try: rgui theme list)"):format(arg), "error")
        return false, false
    end
    if not T.apply(arg, env, settings) then return false, false end
    if type(settings) == "table" then settings.theme = arg end
    return true, type(settings) == "table"
end
