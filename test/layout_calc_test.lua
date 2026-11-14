-- Tests for src/scripts/layout/calc.lua. Run from the repo root: lua test/layout_calc_test.lua
-- COVER=1 prints the lines of calc.lua that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
local path = root .. "/src/scripts/layout/calc.lua"
dofile(path)
local L = rmgui.layout

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end
local function has(s, part, label) eq(type(s) == "string" and s:find(part, 1, true) ~= nil, true, label) end

local function calc(w, cw, mode, saved)
    return L.calc({ windowWidth = w, windowHeight = 900, charWidth = cw, mode = mode, saved = saved })
end

---------------------------------------------------------------- exports
eq(L.LIMITS.minChars, 80, "minChars")
eq(L.LIMITS.top.min, 32, "top min"); eq(L.LIMITS.top.max, 48, "top max"); eq(L.LIMITS.top.default, 36, "top default")
eq(L.LIMITS.chat.min, 260, "chat min"); eq(L.LIMITS.chat.max, 400, "chat max")
eq(L.LIMITS.side.min, 300, "side min"); eq(L.LIMITS.side.max, 440, "side max")
eq(L.LIMITS.chat.default, 0.22, "chat default share"); eq(L.LIMITS.side.default, 0.26, "side default share")
eq(L.clamp(5, 1, 10), 5, "clamp inside"); eq(L.clamp(0, 1, 10), 1, "clamp low")
eq(L.clamp(11, 1, 10), 10, "clamp high"); eq(L.clamp("x", 1, 10), 1, "clamp non-number")
eq(L.clamp(0 / 0, 1, 10), 1, "clamp NaN")

---------------------------------------------------------------- table-driven widths
-- charWidth 8: 80 chars = 640 px
local rows = {
    -- width, layout, left, right, main
    { 600, "compact", 0, 0, 600 },
    { 1000, "compact", 0, 0, 1000 },   -- 640 + 560 = 1200 needed
    { 1199, "compact", 0, 0, 1199 },
    { 1200, "wide", 260, 300, 640 },   -- exact minimum fit, defaults 264/312 shrink
    { 1280, "wide", 282, 333, 665 },
    { 1600, "wide", 352, 416, 832 },
    { 1920, "wide", 400, 440, 1080 },
    { 2560, "wide", 400, 440, 1720 },
    { 3840, "wide", 400, 440, 3000 },
}
for _, r in ipairs(rows) do
    local w, lay, l, rt, m = r[1], r[2], r[3], r[4], r[5]
    local res = calc(w, 8)
    local tag = " @" .. w
    eq(res.layout, lay, "layout" .. tag)
    eq(res.left, l, "left" .. tag); eq(res.right, rt, "right" .. tag)
    eq(res.mainWidth, m, "mainWidth" .. tag)
    eq(res.mainChars, m / 8, "mainChars" .. tag)
    eq(res.bottom, 0, "bottom" .. tag); eq(res.top, 36, "top" .. tag)
    eq(type(res.reason) == "string" and res.reason ~= "", true, "reason" .. tag)
    if lay == "wide" then eq(res.mainChars >= 80, true, "80 chars" .. tag) end
end

---------------------------------------------------------------- 80 character boundary
-- width 1200 (cw 8): defaults 264+312, main 624 = 78 chars, shrinks to exactly 80
local r = calc(1200, 8)
eq(r.mainChars, 80, "boundary exact 80 at minimum columns")
eq(r.reason, "columns shrunk", "boundary reason")
r = calc(1199, 8)
eq(r.layout, "compact", "one pixel under the minimum fit is compact")
has(r.reason, "narrow", "compact reason")
-- defaults leave exactly 80: W - 0.48W = 640 -> W = 1230.77; use saved sizes for an exact hit
r = calc(1200, 8, "auto", { chatWidth = 260, sideWidth = 300 })
eq(r.mainChars, 80, "saved at minimum gives exactly 80")
eq(r.reason, "fits", "exactly 80 needs no shrink")
eq(r.left, 260, "no shrink left"); eq(r.right, 300, "no shrink right")
r = calc(1201, 8, "auto", { chatWidth = 261, sideWidth = 300 })
eq(r.mainChars, 80, "saved leaves exactly 80 with +1 window")
eq(r.reason, "fits", "boundary fits")
r = calc(1201, 8, "auto", { chatWidth = 262, sideWidth = 300 })
eq(r.reason, "columns shrunk", "79.875 chars shrinks")
eq(r.left + r.right <= 1201 - 640, true, "shrunk sum within budget")
eq(r.left, 261, "shrunk left"); eq(r.right, 300, "shrunk right")

---------------------------------------------------------------- shrink rule
-- proportional to the excess above each minimum
r = calc(1500, 8, "auto", { chatWidth = 400, sideWidth = 440 })
-- budget 860, minSum 560, excess 140+140 -> f = 300/280? no: sum 840 < 860, fits
eq(r.reason, "fits", "no shrink when it fits")
r = calc(1400, 10, "auto", { chatWidth = 400, sideWidth = 440 })
-- budget 600; excess 140 and 140; f = 40/280; each gets floor(20)
eq(r.left, 280, "proportional left"); eq(r.right, 320, "proportional right")
eq(r.mainWidth, 800, "proportional main"); eq(r.mainChars, 80, "proportional 80 chars")
r = calc(1400, 10, "auto", { chatWidth = 300, sideWidth = 440 })
-- excess 40 and 140, f = 40/180 -> floor(8.9)=8, floor(31.1)=31
eq(r.left, 268, "uneven left"); eq(r.right, 331, "uneven right")
eq(r.mainChars >= 80, true, "uneven keeps 80")
-- one column already at its minimum stays there
r = calc(1400, 10, "auto", { chatWidth = 260, sideWidth = 440 })
eq(r.left, 260, "column at minimum stays"); eq(r.right, 340, "other column takes the cut")
eq(r.layout, "wide", "stays wide")

---------------------------------------------------------------- saved sizes
r = calc(3000, 8, "auto", { chatWidth = 100, sideWidth = 100, topHeight = 10 })
eq(r.left, 260, "saved chat too small"); eq(r.right, 300, "saved side too small"); eq(r.top, 32, "saved top too small")
r = calc(3000, 8, "auto", { chatWidth = 9999, sideWidth = 9999, topHeight = 9999 })
eq(r.left, 400, "saved chat too large"); eq(r.right, 440, "saved side too large"); eq(r.top, 48, "saved top too large")
r = calc(3000, 8, "auto", { chatWidth = "wide", sideWidth = {}, topHeight = true })
eq(r.left, 400, "non-numeric chat uses default"); eq(r.right, 440, "non-numeric side uses default")
eq(r.top, 36, "non-numeric top uses default")
r = calc(3000, 8, "auto", { chatWidth = 0 / 0, sideWidth = math.huge, topHeight = -math.huge })
eq(r.left, 400, "NaN chat ignored"); eq(r.right, 440, "inf side ignored"); eq(r.top, 36, "-inf top ignored")
r = calc(3000, 8, "auto", { chatWidth = 300.6, sideWidth = 350.4, topHeight = 40.5 })
eq(r.left, 301, "saved chat rounded"); eq(r.right, 350, "saved side rounded"); eq(r.top, 41, "saved top rounded")
r = calc(3000, 8, "auto", "junk")
eq(r.left, 400, "saved not a table")
r = calc(1000, 8, "compact", { topHeight = 44 })
eq(r.top, 44, "compact keeps saved top")

---------------------------------------------------------------- modes
r = calc(1000, 8, "wide")
eq(r.layout, "wide", "forced wide on a narrow window"); eq(r.reason, "forced wide", "forced wide reason")
eq(r.left, 260, "forced wide left clamped"); eq(r.right, 300, "forced wide right clamped")
eq(r.mainWidth, 440, "forced wide main")
r = calc(500, 8, "wide")
eq(r.mainWidth, 0, "forced wide never negative"); eq(r.mainChars, 0, "forced wide chars 0")
r = calc(3840, 8, "wide")
eq(r.left, 400, "forced wide big window")
r = calc(3840, 8, "compact")
eq(r.layout, "compact", "forced compact"); eq(r.reason, "forced compact", "forced compact reason")
eq(r.left, 0, "compact left"); eq(r.right, 0, "compact right")
eq(r.mainWidth, 3840, "compact main is the window"); eq(r.mainChars, 480, "compact chars"); eq(r.top, 36, "compact top")
r = calc(3840, 8, "bogus")
eq(r.layout, "wide", "unknown mode is auto"); eq(r.reason, "fits", "unknown mode reason")
eq(calc(3840, 8, nil).layout, "wide", "nil mode is auto")
eq(calc(3840, 8, 5).layout, "wide", "non-string mode is auto")
eq(calc(3840, 8, "auto").layout, "wide", "auto")
eq(calc(1000, 8, "bogus").layout, "compact", "unknown mode narrow is compact")

---------------------------------------------------------------- invalid input
local bad = { "nil", "string", "NaN", "inf", "-inf", "zero", "negative", "table" }
local vals = { nil, "x", 0 / 0, math.huge, -math.huge, 0, -5, {} }
for i = 1, 8 do
    local v = vals[i]
    for _, case in ipairs({ "window", "char" }) do
        local o = { windowHeight = 900 }
        if case == "window" then o.windowWidth, o.charWidth = v, 8 else o.windowWidth, o.charWidth = 1920, v end
        local ok, res = pcall(L.calc, o)
        local tag = " (" .. case .. " " .. bad[i] .. ")"
        eq(ok, true, "no raise" .. tag)
        eq(res.layout, "compact", "invalid is compact" .. tag)
        eq(res.reason, "invalid window size", "invalid reason" .. tag)
        eq(res.left, 0, "invalid left" .. tag); eq(res.right, 0, "invalid right" .. tag); eq(res.bottom, 0, "invalid bottom" .. tag)
        eq(type(res.top), "number", "invalid top" .. tag)
        eq(res.mainChars, 0, "invalid chars" .. tag)
        eq(res.mainWidth, case == "window" and 0 or 1920, "invalid main" .. tag)
    end
end
for _, o in ipairs({ "x", 5, true }) do
    local ok, res = pcall(L.calc, o)
    eq(ok and res.reason, "invalid window size", "non-table opts " .. tostring(o))
end
eq(pcall(L.calc), true, "no argument")
r = L.calc({ windowWidth = 1920, charWidth = 8, mode = "wide" })
eq(L.calc({ windowWidth = 1920, charWidth = 0, mode = "wide" }).layout, "compact", "invalid beats forced wide")

---------------------------------------------------------------- determinism, no mutation
local opts = { windowWidth = 1280, windowHeight = 720, charWidth = 8, mode = "auto",
    saved = { chatWidth = 350, sideWidth = 400, topHeight = 40 } }
local a, b = L.calc(opts), L.calc(opts)
for k, v in pairs(a) do eq(b[k], v, "deterministic " .. k) end
eq(opts.windowWidth, 1280, "opts width kept"); eq(opts.mode, "auto", "opts mode kept")
eq(opts.saved.chatWidth, 350, "saved chat kept"); eq(opts.saved.sideWidth, 400, "saved side kept")
eq(opts.saved.topHeight, 40, "saved top kept")
local n = 0
for _ in pairs(opts) do n = n + 1 end
eq(n, 5, "opts has no new keys")
a.left = 1
eq(L.calc(opts).left == 1, false, "result is a fresh table")
eq(L.LIMITS.minChars, 80, "limits untouched")

---------------------------------------------------------------- sweep: invariants
for w = 600, 3840, 7 do
    for _, cw in ipairs({ 6, 7.5, 8, 9, 12 }) do
        local res = calc(w, cw)
        if res.layout == "wide" then
            eq(res.mainChars >= 80, true, "sweep 80 chars " .. w .. "/" .. cw)
            eq(res.left >= 260 and res.left <= 400 and res.right >= 300 and res.right <= 440, true, "sweep limits " .. w)
            eq(res.left + res.right + res.mainWidth, w, "sweep sums " .. w)
        else
            eq(res.mainWidth, w, "sweep compact " .. w)
        end
    end
end

if COVER then
    debug.sethook()
    local missed = {}
    local n = 0
    for line in io.lines(path) do
        n = n + 1
        local code = line:gsub("%-%-.*", ""):match("^%s*(.-)%s*$")
        if code ~= "" and code ~= "end" and code ~= "else" and code ~= "}" and code ~= "})" and not hit[path:gsub("^%./", "") .. ":" .. n] and not hit[path .. ":" .. n] then
            missed[#missed + 1] = n .. ": " .. line
        end
    end
    print(#missed == 0 and "COVER: every source line ran" or "COVER: lines no test ran")
    for _, m in ipairs(missed) do print("  " .. m) end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
