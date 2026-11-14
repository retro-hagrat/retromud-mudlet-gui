-- theme/logic: pure Lua theme logic (merge, contrast, stylesheets, image lookup).
-- No Mudlet or Geyser calls. See doc/spec/theming.md.
rmgui = rmgui or {}
rmgui.theme = rmgui.theme or {}
local T = rmgui.theme

T.roles = { "window", "statusbar", "panel", "button", "tab", "tabActive" }

local function copy(v)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do c[k] = copy(x) end
    return c
end

local function isColor(v)
    if type(v) ~= "table" or (#v ~= 3 and #v ~= 4) then return false end
    for i = 1, #v do
        if type(v[i]) ~= "number" or v[i] < 0 or v[i] > 255 or v[i] % 1 ~= 0 then return false end -- whole channels: the stylesheet formatter needs integers
    end
    return true
end

-- Put the valid keys of `over` into `out`. `base` is the schema: a key must exist
-- there and keep its type. A bad key is skipped and reported (THEME-010).
local function overlay(out, base, over, path, problems)
    for k, v in pairs(over) do
        local p, b = path .. tostring(k), base[k]
        local bad
        if b == nil then bad = "unknown key"
        elseif isColor(b) then bad = not isColor(v) and "not a colour"
        elseif type(b) == "table" then
            if type(v) == "table" then overlay(out[k], b, v, p .. ".", problems) else bad = "expected a table" end
        elseif b == false then bad = not (type(v) == "string" or v == false) and "expected a file name or false"
        elseif type(v) ~= type(b) then bad = "expected a " .. type(b)
        elseif type(v) == "number" and v <= 0 then bad = "must be above 0"
        elseif k == "imageScale" and v % 1 ~= 0 then bad = "must be a whole number" end
        if bad then problems[#problems + 1] = p .. ": " .. bad
        elseif type(b) ~= "table" or isColor(b) then out[k] = copy(v) end
    end
end

-- The named preset, filled from the default theme, with the player's override on top.
-- Returns the theme and a list of problems, or nil and a reason.
function T.resolve(name, override)
    local preset = T.presets[name]
    if not preset then return nil, "unknown theme: " .. tostring(name) end
    local base = T.presets[T.default]
    local problems, theme = {}, copy(base)
    overlay(theme, base, preset, "", problems)
    overlay(theme, copy(theme), override or {}, "", problems)
    return theme, problems
end

local function lin(c)
    c = c / 255
    return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
end
local function lum(c) return 0.2126 * lin(c[1]) + 0.7152 * lin(c[2]) + 0.0722 * lin(c[3]) end

-- WCAG contrast ratio. shortcut: alpha is ignored, so a translucent colour is
-- judged as if solid; add compositing if a preset uses alpha for text.
function T.contrast(a, b)
    local x, y = lum(a), lum(b)
    if x < y then x, y = y, x end
    return (x + 0.05) / (y + 0.05)
end

-- THEME-013. Returns one string for each pair below its limit.
function T.contrastProblems(theme)
    local c, bad = theme.colors, {}
    local function check(fg, bg, name, limit)
        local r = T.contrast(fg, bg)
        if r < limit then bad[#bad + 1] = ("%s: %.2f (needs %.1f)"):format(name, r, limit) end
    end
    for _, bgName in ipairs({ "surface", "surfaceAlt" }) do
        for _, fg in ipairs({ "text", "textMuted" }) do check(c[fg], c[bgName], fg .. " on " .. bgName, 4.5) end
    end
    check(c.accent, c.surface, "accent on surface", 3)
    check(c.accent, c.surfaceAlt, "accent on surfaceAlt", 3)
    for _, k in ipairs({ "good", "warn", "danger", "hp", "sp", "ep" }) do check(c[k], c.surface, k .. " on surface", 3) end
    check(c.map.exits, c.map.background, "map exits on map background", 3)
    return bad
end

local function rgba(c)
    if c[4] and c[4] < 255 then return ("rgba(%d,%d,%d,%d)"):format(c[1], c[2], c[3], c[4]) end
    return ("rgb(%d,%d,%d)"):format(c[1], c[2], c[3])
end

-- Which colours each role uses.
local STYLE = {
    window = { bg = "surface", fg = "text" },
    statusbar = { bg = "surfaceAlt", fg = "text" },
    panel = { bg = "surface", fg = "text", border = "border" },
    button = { bg = "surfaceAlt", fg = "text", border = "border", hover = "accent" },
    tab = { bg = "surfaceAlt", fg = "textMuted", border = "border" },
    tabActive = { bg = "surface", fg = "text", border = "accent" },
}

-- Image slices (top, right, bottom, left) in image pixels: the art contract of
-- doc/spec/theming.md. The window role has no slices because it is a tile.
local NINE = {
    panel = { 16, 16, 16, 16 }, statusbar = { 8, 16, 8, 16 }, button = { 12, 12, 12, 12 },
    tab = { 12, 12, 12, 12 }, tabActive = { 12, 12, 12, 12 }, -- tabs use the button art
}

-- Stylesheet for a Geyser label. The rule is wrapped in QLabel{} so a tooltip does not
-- inherit it. An image is nine-slice: the corners stay sharp at imageScale times their
-- size and the edges and the middle repeat. `repeat` and not `round`: round rescales the
-- tile with smoothing, which draws dark seam lines (seen in Mudlet). Plain stretching smears pixel art (tested in
-- Mudlet). A window image is a tile at its own size. Text sits on top of the image.
-- An unsafe image path is ignored (THEME-008). shortcut: no hover look with an image;
-- add a second image per role if players want one.
function T.css(role, theme, imagePath)
    local s = STYLE[role]
    if not s then return nil, "unknown role: " .. tostring(role) end
    local c, f = theme.colors, theme.fonts
    local fill = "background-color: " .. rgba(c[s.bg]) .. ";"
    local border = s.border and ("border: 1px solid " .. rgba(c[s.border]) .. ";")
    local hover = s.hover
    if imagePath and not imagePath:find('["\n\r]') then
        local path, n, k = imagePath:gsub("\\", "/"), NINE[role], theme.imageScale
        if n then
            fill = ('border-image: url("%s") %d %d %d %d repeat repeat;'):format(path, n[1], n[2], n[3], n[4])
            border = ("border-width: %dpx %dpx %dpx %dpx;"):format(n[1] * k, n[2] * k, n[3] * k, n[4] * k)
        else
            fill = ('background-image: url("%s"); background-repeat: repeat;'):format(path)
        end
        hover = nil
    end
    local parts = { fill, "color: " .. rgba(c[s.fg]) .. ";", ("font-size: %dpt;"):format(f.size) }
    if border then parts[#parts + 1] = border end
    if f.family ~= "" and not f.family:find('["\n\r;{}]') then
        parts[#parts + 1] = ('font-family: "%s";'):format(f.family)
    end
    local out = "QLabel{" .. table.concat(parts, " ") .. "}"
    if hover then out = out .. "QLabel::hover{border: 1px solid " .. rgba(c[hover]) .. ";}" end
    return out
end

-- Hex text colour of a role. A Geyser label draws echo text in its own colour and ignores
-- the stylesheet colour (seen in Mudlet), so an element passes this to label:echo(text, colour).
function T.textColor(role, theme)
    local s = STYLE[role]
    if not s then return nil, "unknown role: " .. tostring(role) end
    local c = theme.colors[s.fg]
    return ("#%02X%02X%02X"):format(c[1], c[2], c[3])
end

-- THEME-009. The player's folder wins over the folder of the theme.
-- dirs = { player = "<profile>/retromud-gui-theme", themes = "<package dir>/themes" }.
function T.findImage(role, themeName, dirs, exists)
    local candidates = {
        dirs.player .. "/" .. role .. ".png",
        dirs.themes .. "/" .. themeName .. "/" .. role .. ".png",
    }
    for _, path in ipairs(candidates) do
        if exists(path) then return path end
    end
end
