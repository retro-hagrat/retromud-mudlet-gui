-- themepicker/glue: a button in the "picker" layout slot that opens a panel with one row per theme.
-- Each row is drawn in its own theme. Talks to Mudlet only through env and Geyser.
rmgui = rmgui or {}
rmgui.themepicker = rmgui.themepicker or {}

local P = rmgui.themepicker
P.state = P.state or {}
-- the editor re-runs this file while the old instance is live: stop it (its locals are unreachable later), restart below
local prevEnv = P.state.env
if P.teardown then pcall(P.teardown) end

local PREFIX = "rmgui.picker."
local ELEMENT = "picker.button"
local PANEL_W, ROW_H, GAP, PAD = 220, 40, 4, 4
local st = P.state

local function reset()
    for k in pairs(st) do st[k] = nil end
    st.rows, st.ids, st.said = {}, {}, {}
end
reset()

local function say(msg, level)
    if st.env and type(st.env.say) == "function" then pcall(st.env.say, msg, level) end
end

-- say each distinct failure once so a broken call cannot flood the main window
local function report(where, err)
    local msg = where .. ": " .. tostring(err)
    if st.said[msg] then return end
    st.said[msg] = true
    say(msg, "err")
end

local function del(o) if o then pcall(o.delete, o) end end

local function rgb(c) return ("rgb(%d,%d,%d)"):format(c[1], c[2], c[3]) end

local function activeName()
    local n = st.ctx and st.ctx.name
    if not n then
        local ok, a = pcall(rmgui.theme.active)
        n = ok and a or nil
    end
    return n or rmgui.theme.default
end

local function activeTheme()
    if st.ctx and st.ctx.theme then return st.ctx.theme end
    local ok, t = pcall(rmgui.theme.resolve, activeName())
    return ok and t or nil
end

local function titleOf(name)
    local p = rmgui.theme.presets and rmgui.theme.presets[name]
    return p and p.title or name
end

local function plainStyle(bg, border, th)
    return ("QLabel{background-color: %s; color: %s; border: 1px solid %s; font-size: %dpt;}")
        :format(rgb(th.colors[bg]), rgb(th.colors.text), rgb(th.colors[border]), th.fonts.size)
end

local function drawButton()
    local b = st.button
    if not b then return end
    local ok, err = pcall(function()
        -- the name is centred and the arrow sits at the far right, so it does not read as part of the name
        local text = ("<table width='100%%' cellspacing='0' cellpadding='0'><tr><td width='15%%'></td><td align='center'>%s</td>"
            .. "<td width='15%%' align='right'>v&nbsp;</td></tr></table>"):format(titleOf(activeName()))
        if not st.ctx then b:echo(text) return end
        b:setStyleSheet(plainStyle("surfaceAlt", "accent", st.ctx.theme))
        b:echo(text, st.ctx.textColor("button"))
    end)
    if not ok then report("button", err) end
end

local function close()
    del(st.panel); del(st.backdrop)
    for _, r in ipairs(st.rows) do del(r) end
    st.panel, st.backdrop, st.rows = nil, nil, {}
end

local function pick(name)
    if name == activeName() then close() return end
    local ok, done, changed = pcall(rmgui.theme.command, name, st.env, st.env.settings)
    if ok and done and changed then
        local ok2, err = pcall(st.env.saveSettings)
        if not ok2 then report("save", err) end
    elseif not ok then report("theme", done) end
    close()
end

local function open()
    close()
    local ok, err = pcall(function()
        local th = activeTheme()
        local ww, wh = st.env.windowSize()
        local list = rmgui.theme.list()
        local h = #list * ROW_H + (#list - 1) * GAP + 2 * PAD
        local w = math.min(PANEL_W, ww)
        -- right edge on the button's right edge, then pulled inside the window
        local x = math.max(0, math.min(st.button:get_x() + st.button:get_width() - w, ww - w))
        local y = math.max(0, math.min(st.button:get_y() + st.button:get_height(), wh - h))

        st.backdrop = Geyser.Label:new({ name = PREFIX .. "backdrop", x = 0, y = 0, width = ww, height = wh })
        st.backdrop:setStyleSheet("QLabel{background-color: rgba(0,0,0,0);}")
        st.backdrop:setClickCallback(function() close() end)
        st.panel = Geyser.Label:new({ name = PREFIX .. "panel", x = x, y = y, width = w, height = h })
        st.panel:setStyleSheet(plainStyle("surface", "accent", th))
        pcall(st.panel.raise, st.panel)
        local current = activeName()
        for i, t in ipairs(list) do
            local row = Geyser.Label:new({
                name = PREFIX .. "row." .. t.name, x = PAD, y = PAD + (i - 1) * (ROW_H + GAP),
                width = w - 2 * PAD, height = ROW_H,
            }, st.panel)
            st.rows[#st.rows + 1] = row
            local rt = rmgui.theme.resolve(t.name)
            local path = rmgui.theme.findImage("button", t.name, st.env.dirs, st.env.exists)
            row:setStyleSheet(rmgui.theme.css("button", rt, path))
            row:echo(t.title .. (t.name == current and "  (current)" or ""), rmgui.theme.textColor("button", rt))
            row:setClickCallback(function() pick(t.name) end)
            pcall(row.raise, row)
        end
    end)
    if not ok then close() report("panel", err) end
end

local function toggle()
    if st.panel then close() else open() end
end

local function hint()
    local s = st.env.settings
    if type(s) ~= "table" then return end
    if type(s.ui) ~= "table" then s.ui = { hintShown = false } end
    if s.ui.hintShown == true then return end
    say("tip: click the theme button at the top right, or type rgui theme", "info")
    s.ui.hintShown = true
    pcall(st.env.saveSettings)
end

local function build()
    local ok, slot = pcall(function() return rmgui.layout and rmgui.layout.get("picker") end)
    if not ok or not slot then return end
    if st.button then
        if st.button.parent == slot then drawButton() return end -- the layout was rebuilt otherwise
        del(st.button)
        st.button = nil
    end
    local made, b = pcall(Geyser.Label.new, Geyser.Label,
        { name = PREFIX .. "button", x = 0, y = 0, width = "100%", height = "100%" }, slot)
    if not made or not b then report("button", b) return end
    st.button = b
    pcall(b.setClickCallback, b, toggle)
    pcall(b.setToolTip, b, "Change the look")
    drawButton()
    hint()
end

local function guarded(name, fn)
    return function()
        local ok, err = pcall(fn)
        if not ok then report(name, err) end
    end
end

function P.init(e)
    P.teardown()
    if type(e) ~= "table" then return end
    st.env = e
    local function on(event, fn)
        local ok, id = pcall(e.registerEvent, event, guarded(event, fn))
        if ok and id then st.ids[#st.ids + 1] = id end
    end
    pcall(rmgui.theme.register, ELEMENT, function(c)
        st.ctx = c
        close()
        drawButton()
    end)
    on("rmgui.onLayout", function() close() build() end)
    on("sysWindowResizeEvent", close)
    build()
end

function P.teardown()
    close()
    del(st.button)
    if st.env then
        for _, id in ipairs(st.ids) do pcall(st.env.killEvent, id) end
    end
    if rmgui.theme and rmgui.theme.unregister then pcall(rmgui.theme.unregister, ELEMENT) end
    reset()
end

rmgui.core.register("themepicker", { init = P.init, teardown = P.teardown })
if prevEnv then pcall(P.init, prevEnv) end
