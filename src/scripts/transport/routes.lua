-- transport/routes: blind speedwalks to the world exits, from https://retrowiki.wikidot.com/world-exits
-- (page revision 2125, 18 Jul 2025). Each route only works from the start room named in its group.
-- Raji's exits drift and the daily statue/ship/shaft table changes each boot, so neither is here.
-- shortcut: no check of the start room; upgrade when the mapper can say where the player is.
rmgui = rmgui or {}
rmgui.transport = rmgui.transport or {}
local T = rmgui.transport

T.groups = {
    shaft = { -- from Ngate Igneous (given by the player; the wiki does not name the start)
        start = "Ngate Igneous",
        routes = {
            ["0"] = "n;4 ne;2 n",
            ["1"] = "sw;11 w;3 sw;2 s;3 se;8 e;5 se;sw;4 s;5 se;2 sw",
            ["2"] = "sw;11 w;3 sw;3 s;3 se;9 e;4 se;2 e;ne;n;ne",
            ["3"] = "sw;13 w;5 sw;2 w;sw;2 se;s",
            ["4"] = "sw;13 w;5 sw;2 w;sw;w;9 nw;w",
            ["5"] = "sw;13 w;5 sw;w;sw;2 w;3 sw;w;d;2 se",
            ["6"] = "sw;13 w;5 sw;w;sw;2 w;3 sw;w;d;sw;s;sw;w;sw;s;2 se;u;se;2 e;3 ne",
            ["7"] = "sw;13 w;5 sw;w;sw;2 w;3 sw;w;d;sw;s;sw;w;sw;s;2 se;u;2 se;u;2 s;3 se;3 e;5 ne;2 e;2 ne;2 nw",
            ["8"] = "sw;13 w;5 sw;w;sw;2 w;3 sw;w;d;sw;s;sw;w;sw;s;2 se;u;2 se;u;2 s;5 se;2 s;2 sw;4 w",
            ["9"] = "sw;13 w;5 sw;w;sw;2 w;3 sw;w;d;sw;s;sw;w;sw;s;2 se;u;2 se;u;2 s;3 se;7 e;ne;e;se;e;se;s",
        },
    },
    ship = { -- from Sgate Sauronan
        start = "Sgate Sauronan",
        routes = {
            bar = "9ne,17e,d,4e,2n,d,n,5ne", esh = "2se,9e", lag = "38e", nep = "9ne,17e,d,4e,2n,d,n,9ne",
            swa = "38e,5ne,5e", toh = "7nw,2d,8nw,3w", tro = "3ne,6n,2d,17n", val = "9ne,17e,d,4e",
            wcl = "nw,8w,4nw,2d,5w", wsh = "nw,8w",
        },
    },
    key = { -- from Ngate Keystone
        start = "Ngate Keystone",
        routes = {
            aba = "4nw,3w,u,w,gate,4w,nw,adv", alt = "sw,8w,path,forest,2sw,8s,altar",
            bio = "2sw,s,charthur,13s,3w,u", gyd = "2sw,s,charthur,14s,w", key = "gate,2s,w,s",
            pal = "gate,4s,4w,2s,w,n", tem = "4nw,3w,u,w,gate,6w,ne,church,w,2s,u,2n,nw,n,ne",
        },
    },
    pod = { -- from Wgate Edon
        start = "Wgate Edon",
        routes = { welstar = "2d,20n,5w", perdow = "2d,8n,12w", wysoom = "2d,2e,6n", crypt = "2d,1s,9e", raji = "2d,19e,2se,3s,2u,1s,1u" },
    },
    grove = { -- pods from the secluded grove (Druid guild exit to the jungle)
        start = "the secluded grove",
        routes = { welstar = "2u,24nw,2d", perdow = "4nw,20w,7nw,n", wysoom = "4nw,7w,6nw", crypt = "3nw,8w", raji = "2e,s,2u,s,u" },
    },
    gate = { -- Perdow gates, from the Quest Shrine in the SW corner
        start = "the Quest Shrine (SW corner of Perdow)",
        routes = { crypt = "6e,98n", perdow = "43e,4n", raji = "46e,27n", sosel = "13e,23n", welstar = "5e,44n",
            wysoom = "49e,76n", castle = "17e,70n", cave = "35e,90n", pocket = "17e,80n" },
    },
}

local MAX_STEPS = 200

-- "sw;13 w;#2 s;9ne, d " -> { "sw", "w" x13, ... }. Returns nil, why on a token it cannot read.
function T.expand(path)
    local out = {}
    for tok in tostring(path):gmatch("[^;,]+") do
        local n, cmd = tok:match("^%s*#?(%d*)%s*([%a]+)%s*$")
        if not cmd then return nil, "cannot read step '" .. tok .. "'" end
        n = tonumber(n) or 1
        if n < 1 or #out + n > MAX_STEPS then return nil, "route too long at '" .. tok .. "'" end
        for _ = 1, n do out[#out + 1] = cmd end
    end
    return out
end

local function names(group)
    local ks = {}
    for k in pairs(T.groups[group].routes) do ks[#ks + 1] = k end
    table.sort(ks)
    return table.concat(ks, ", ")
end

-- Output is cecho markup in the colours of rmap: a cyan tag, green for done, red for a refusal.
function T.say(text, level)
    local color = level == "ok" and "green" or level == "err" and "red" or "cyan"
    _G.cecho(("<%s>[wt]<reset> %s\n"):format(color, text))
end

function T.help()
    local lines = { "<white>world transport<reset>: wt <<kind>> <<name>>. A blind walk, so start where it says." }
    for _, g in ipairs({ "shaft", "ship", "key", "pod", "grove", "gate" }) do
        lines[#lines + 1] = ("  <cyan>wt %s<reset> <yellow><%s><reset> <grey>from %s<reset>")
            :format(g, names(g):gsub(", ", "|"), T.groups[g].start)
    end
    return lines
end

-- Sends one command per step. `out` prints messages and `send` sends a command; both default to Mudlet's.
function T.go(kind, name, send, out)
    send, out = send or _G.send, out or T.say
    local g = T.groups[kind]
    local path = g and g.routes[tostring(name or ""):lower()]
    if not path then
        local known = g and names(kind):gsub(", ", "|") or "none"
        out(("unknown <yellow>%s %s<reset>. Known: <yellow>%s<reset>"):format(tostring(kind):gsub("<", "<<"), tostring(name):gsub("<", "<<"), known), "err")
        return false
    end
    local steps, why = T.expand(path)
    if not steps then out(why, "err") return false end
    out(("<cyan>%s %s<reset>: %d steps from <grey>%s<reset>"):format(kind, name, #steps, g.start), "ok")
    for _, s in ipairs(steps) do send(s, false) end
    return true
end
