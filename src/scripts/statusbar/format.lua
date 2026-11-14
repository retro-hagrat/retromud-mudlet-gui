-- statusbar/format: pure Lua status bar text. No Mudlet or Geyser calls.
-- See doc/design.md (Status bar rules) and doc/spec/layout.md.
rmgui = rmgui or {}
rmgui.statusbar = rmgui.statusbar or {}
local S = rmgui.statusbar

local STATES = { SYNCED = true, PENDING = true, UNSYNCED = true }

local function clean(v)
    if type(v) ~= "string" then return nil end
    v = v:gsub("%c", " "):gsub(" +", " "):match("^ *(.-) *$")
    if v == "" then return nil end
    return v
end

-- shortcut: lengths count UTF-8 characters, not display width, upgrade if wide glyphs matter.
local function len(s) return utf8.len(s) or #s end
local function head(s, n)
    if not utf8.len(s) then return s:sub(1, n) end
    return s:sub(1, utf8.offset(s, n + 1) - 1)
end

local function validMax(m)
    return type(m) == "number" and m > 0 and m == math.floor(m) and m or nil
end

function S.format(state, opts)
    if type(state) ~= "table" then state = {} end
    local max = validMax(type(opts) == "table" and opts.maxChars or nil)
    local parts = { clean(state.roomName) or "no room yet" }
    if state.mapperInstalled ~= true then
        parts[2] = "(mapper not installed)"
    elseif state.mapping == true and STATES[state.syncState] then
        local area = clean(state.areaName)
        if area and state.syncState ~= "UNSYNCED" then parts[#parts + 1] = area end
        parts[#parts + 1] = "[" .. state.syncState .. "]"
    end
    local text = table.concat(parts, "  ")
    if max then
        -- drop the last part first: state, then area, then the notice
        while len(text) > max and #parts > 1 do
            parts[#parts] = nil
            text = table.concat(parts, "  ")
        end
        if len(text) > max then
            parts[1] = max < 4 and head(parts[1], max) or head(parts[1], max - 3) .. "..."
            text = parts[1]
        end
    end
    return { text = text, parts = parts }
end
