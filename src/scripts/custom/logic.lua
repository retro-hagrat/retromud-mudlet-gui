-- custom/logic: pure Lua. The twelve player buttons: what a saved entry may hold, and how to clean it.
rmgui = rmgui or {}
rmgui.custom = rmgui.custom or {}
local C = rmgui.custom

C.COUNT, C.COLS = 12, 4
C.MAX_LABEL, C.MAX_COMMAND = 12, 200

-- One line of printable text, trimmed, cut to max characters. Returns nil for anything else.
function C.clean(s, max)
    if type(s) ~= "string" then return nil end
    s = s:gsub("[%c]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return nil end
    return s:sub(1, max)
end

-- The saved list is { {slot = 3, label = "heal", command = "cast heal"}, ... }. A bad entry is dropped.
-- Returns slots[1..12] = {label, command} (holes where nothing is set) and the number of dropped entries.
function C.decode(list)
    local slots, dropped = {}, 0
    if type(list) ~= "table" then return slots, 0 end
    for _, e in ipairs(list) do
        local n = type(e) == "table" and e.slot
        local label = type(e) == "table" and C.clean(e.label, C.MAX_LABEL)
        local command = type(e) == "table" and C.clean(e.command, C.MAX_COMMAND)
        if type(n) == "number" and n == math.floor(n) and n >= 1 and n <= C.COUNT and label and command and not slots[n] then
            slots[n] = { label = label, command = command }
        else
            dropped = dropped + 1
        end
    end
    return slots, dropped
end

function C.encode(slots)
    local list = {}
    for n = 1, C.COUNT do
        local s = slots[n]
        if s then list[#list + 1] = { slot = n, label = s.label, command = s.command } end
    end
    return list
end

-- Set a slot, or clear it when label and command are both empty. Returns ok, reason.
function C.set(slots, n, label, command)
    if type(n) ~= "number" or n ~= math.floor(n) or n < 1 or n > C.COUNT then return false, "no such button" end
    local l, c = C.clean(label, C.MAX_LABEL), C.clean(command, C.MAX_COMMAND)
    if not l and not c then slots[n] = nil return true end
    if not c then return false, "the command is empty" end
    slots[n] = { label = l or c:sub(1, C.MAX_LABEL), command = c } -- no name: use the start of the command
    return true
end
