rmgui = rmgui or {}
rmgui.vitals = rmgui.vitals or {}

local V = rmgui.vitals
local LIMIT = 1000000000
local FIELDS = { "hp", "hpMax", "sp", "spMax", "ep", "epMax", "gold", "exp" }

function V.isPromptLine(line)
    return type(line) == "string" and line:sub(1, 3) == "Hp:"
end

local function num(s)
    local n = tonumber(s)
    if n and n >= -LIMIT and n <= LIMIT then return n end
end

-- Reads "Label: cur/max" at pos. Returns cur, max, next pos; or nil.
local function pair(line, pos, label)
    local c, m, e = line:match("^" .. label .. ": ?(-?%d+)/(%d+)()", pos)
    if not c then return nil end
    c, m = num(c), num(m)
    if not c or not m or m <= 0 then return nil end
    return c, m, e
end

function V.parse(line)
    if not V.isPromptLine(line) then return nil end
    local r = {}
    local pos = 1
    for _, k in ipairs({ "Hp", "Sp", "Ep" }) do
        local c, m, e = pair(line, pos, k)
        if not c then return nil end
        local low = k:lower()
        r[low], r[low .. "Max"] = c, m
        pos = e
        if k ~= "Ep" then
            local _, sp = line:find("^ +", pos)
            if not sp then return nil end
            pos = sp + 1
        end
    end
    while true do
        local _, sp = line:find("^ +", pos)
        if not sp then return nil end
        pos = sp + 1
        if line:sub(pos, pos) == ">" then return r end
        local label, v, e = line:match("^(%a+): ?(-?%d+)()", pos)
        local key = label == "Gold" and "gold" or label == "Exp" and "exp" or nil
        -- Gold must come before Exp, each at most once.
        if not key or r[key] ~= nil or (key == "gold" and r.exp ~= nil) then return nil end
        v = num(v)
        if not v then return nil end
        r[key] = v
        pos = e
    end
end

function V.changed(old, new)
    if type(new) ~= "table" then return false end
    if type(old) ~= "table" then return true end
    for _, k in ipairs(FIELDS) do
        if old[k] ~= new[k] then return true end
    end
    return false
end

function V.percent(cur, max)
    if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then return 0 end
    local p = math.floor(cur * 100 / max)
    if p ~= p then return 0 end
    return math.max(0, math.min(100, p))
end
