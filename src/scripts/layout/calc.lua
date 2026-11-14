-- layout/calc: pure Lua layout sizes (wide or compact). No Mudlet or Geyser calls.
-- See doc/spec/layout.md sections 4 to 7.
rmgui = rmgui or {}
rmgui.layout = rmgui.layout or {}
local L = rmgui.layout

L.LIMITS = {
    top = { min = 32, max = 48, default = 36 },
    -- chat and side defaults are a share of the window width, not pixels
    chat = { min = 260, max = 400, default = 0.22 },
    side = { min = 300, max = 440, default = 0.26 },
    minChars = 80,
}

local function isNum(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function round(v) return math.floor(v + 0.5) end

function L.clamp(v, min, max)
    if not isNum(v) then return min end
    if v < min then return min end
    if v > max then return max end
    return v
end

-- A saved size wins over the default; a bad saved value is ignored.
local function size(lim, saved, fallback)
    return L.clamp(round(isNum(saved) and saved or fallback), lim.min, lim.max)
end

function L.calc(opts)
    if type(opts) ~= "table" then opts = {} end
    local saved = type(opts.saved) == "table" and opts.saved or {}
    local lim = L.LIMITS
    local W, cw = opts.windowWidth, opts.charWidth
    local valid = isNum(W) and W > 0 and isNum(cw) and cw > 0
    local width = isNum(W) and W > 0 and round(W) or 0
    local top = size(lim.top, saved.topHeight, lim.top.default)

    local function compact(reason)
        return {
            layout = "compact", top = top, left = 0, right = 0, bottom = 0,
            mainWidth = width, mainChars = valid and width / cw or 0, reason = reason,
        }
    end
    if not valid then return compact("invalid window size") end

    local mode = opts.mode
    if mode ~= "wide" and mode ~= "compact" then mode = "auto" end
    if mode == "compact" then return compact("forced compact") end

    local left = size(lim.chat, saved.chatWidth, W * lim.chat.default)
    local right = size(lim.side, saved.sideWidth, W * lim.side.default)
    local reason = mode == "wide" and "forced wide" or "fits"

    if mode == "auto" and (width - left - right) / cw < lim.minChars then
        local budget = width - math.ceil(lim.minChars * cw)
        local minSum = lim.chat.min + lim.side.min
        if budget < minSum then return compact("window too narrow") end
        -- Floor keeps the sum at or under the budget, so the main window never ends below 80.
        local f = (budget - minSum) / (left + right - minSum)
        left = lim.chat.min + math.floor((left - lim.chat.min) * f)
        right = lim.side.min + math.floor((right - lim.side.min) * f)
        reason = "columns shrunk"
    end

    local main = math.max(width - left - right, 0)
    return {
        layout = "wide", top = top, left = left, right = right, bottom = 0,
        mainWidth = main, mainChars = main / cw, reason = reason,
    }
end
