-- party/parser: pure parser for the party status block of the `pssa` command.
rmgui = rmgui or {}
rmgui.party = rmgui.party or {}

local P = rmgui.party
P.MAX = 8
local LIMIT = 1000000000

function P.isRule(line)
    return type(line) == "string" and line:match("^=====+%s*$") ~= nil
end

local function num(s)
    local n = tonumber(s)
    if n and n >= -LIMIT and n <= LIMIT then return n end
end

-- One member row: "|Name | HP: 1/2 | SP: 1/2 | EP: 1/2 |". Returns a table or nil.
function P.parseRow(line)
    if type(line) ~= "string" then return nil end
    local name, hp, hpM, sp, spM, ep, epM = line:match(
        "^|%s*([^|]-)%s*|%s*HP:%s*(-?%d+)/(%d+)%s*|%s*SP:%s*(-?%d+)/(%d+)%s*|%s*EP:%s*(-?%d+)/(%d+)%s*|")
    if not name or name == "" then return nil end
    local r = { name = name, hp = num(hp), hpMax = num(hpM), sp = num(sp), spMax = num(spM), ep = num(ep), epMax = num(epM) }
    for _, k in ipairs({ "hp", "hpMax", "sp", "spMax", "ep", "epMax" }) do
        if not r[k] then return nil end
    end
    if r.hpMax <= 0 or r.spMax <= 0 or r.epMax <= 0 then return nil end
    return r
end

-- Fed one line at a time; rule line opens a block, rows fill it, the next rule closes it.
-- Returns the member list when a block closes, else nil. Any other line drops a half-read block.
function P.feed(state, line)
    if P.isRule(line) then
        local done = state.rows
        state.rows = state.rows == nil and {} or nil
        return done
    end
    if not state.rows then return nil end
    local r = P.parseRow(line)
    if not r or #state.rows >= P.MAX then state.rows = nil return nil end
    state.rows[#state.rows + 1] = r
end
