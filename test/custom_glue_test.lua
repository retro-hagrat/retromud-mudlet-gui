-- Tests for src/scripts/custom/glue.lua against the fake Mudlet. Run from the repo root: lua test/custom_glue_test.lua
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local F = dofile(root .. "/test/fake_mudlet.lua")
local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then fails = fails + 1 print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want))) end
end

local said, elements, slot, env, saves
local function world(opts)
    opts = opts or {}
    F.reset()
    rmgui = nil
    said, elements, saves = {}, {}, 0
    dofile(root .. "/src/scripts/core/lifecycle.lua")
    dofile(root .. "/src/scripts/core/env.lua")
    rmgui.theme = {
        register = function(n, fn) elements[n] = fn return true end,
        unregister = function(n) elements[n] = nil return true end,
    }
    slot = Geyser.Container:new({ name = "slot", x = 0, y = 0, width = 400, height = 108 })
    rmgui.layout = { get = function(s) if s == "custom" and not opts.noSlot then return slot end end }
    dofile(root .. "/src/scripts/custom/logic.lua")
    dofile(root .. "/src/scripts/custom/glue.lua")
    F.expanded = nil
    env = rmgui.core.makeEnv()
    env.say = function(m, l) said[#said + 1] = m end
    env.settings = { custom = opts.saved or {} }
    env.saveSettings = function() saves = saves + 1 end
    return env
end
local function theme()
    elements["custom.buttons"]({
        theme = { colors = { surface = { 1, 2, 3 }, surfaceAlt = { 4, 5, 6 }, text = { 250, 250, 250 }, textMuted = { 120, 120, 120 }, border = { 9, 9, 9 } },
                  fonts = { size = 10, sizeSmall = 9 } },
        css = function(r) return "css-" .. r end, textColor = function(r) return "col-" .. r end,
    })
end
local function B(n) return F.objects["rmgui.custom.button." .. n] end
local function E(n) return F.objects["rmgui.custom.editor." .. n] end
local function expanded() return table.concat(F.expanded or {}, "|") end
local function count_(prefix)
    local n = 0
    for _, o in ipairs(F.objectList) do if o.name:find(prefix, 1, true) == 1 then n = n + 1 end end
    return n
end

---------------------------------------------------------------- build
env = world({ saved = { { slot = 1, label = "heal", command = "cast heal" }, { slot = 99, label = "bad", command = "x" } } })
rmgui.custom.init(env)
eq(count_("rmgui.custom.button."), 12, "twelve buttons")
eq(B(1).parent, slot, "buttons live in the slot")
eq(B(2).text, "+", "an empty button shows a plus before theming"); eq(B(1).text, "heal", "a set button shows its label before theming")
theme()
eq(B(1).text, "heal", "saved label shown"); eq(B(2).text, "+", "empty button shows a plus")
eq(B(1).tooltip:find("cast heal", 1, true) ~= nil, true, "tooltip shows the command")
eq(B(1).textFormat, "c", "label centred")
eq(B(1).styleSheet:find("rgb(4,5,6)", 1, true) ~= nil, true, "button background is surfaceAlt")
eq(B(2).styleSheet:find("color: rgb(120,120,120)", 1, true) ~= nil, true, "empty button is muted")
eq(B(1).textColor, "#FAFAFA", "label drawn in the text colour")
eq(said[1]:find("1 saved button", 1, true) ~= nil, true, "invalid saved entry reported")
-- grid: 4 columns, 3 rows, no overlap, all inside the slot
for n = 1, 12 do
    local b = B(n)
    eq(b:get_x() >= 0 and b:get_x() + b:get_width() <= 400.01 and b:get_y() >= 0 and b:get_y() + b:get_height() <= 108.01, true, "button " .. n .. " inside the slot")
end
eq(B(1):get_y() == B(4):get_y() and B(5):get_y() > B(1):get_y() and B(9):get_y() > B(5):get_y(), true, "three rows of four")
eq(B(1):get_x() + B(1):get_width() <= B(2):get_x(), true, "no overlap in a row")
eq(B(1):get_y() + B(1):get_height() <= B(5):get_y(), true, "no overlap between rows")

---------------------------------------------------------------- sending
B(1):fireClick()
eq(expanded(), "cast heal", "left click sends the command through expandAlias (alias or straight to the game)")
B(1):fireClick(); eq(#F.expanded, 2, "each click sends once")
eq(count_("rmgui.custom.editor"), 0, "a left click on a set button opens no editor")

---------------------------------------------------------------- editing
B(1):fireRightClick()
eq(count_("rmgui.custom.editor") > 0, true, "right click opens the editor")
eq(#F.expanded, 2, "right click does not send")
eq(E("name").typed, "heal", "editor shows the label"); eq(E("command").typed, "cast heal", "editor shows the command")
eq(E("name").styleSheet ~= nil, true, "editor fields are themed")
E("name"):print("big heal"); E("command"):print("cast heal all")
E("save"):fireClick()
eq(B(1).text, "big heal", "saved label drawn"); eq(env.settings.custom[1].command, "cast heal all", "settings updated")
eq(saves, 1, "settings saved once")
eq(count_("rmgui.custom.editor"), 0, "editor closed after save")
B(1):fireClick(); eq(F.expanded[#F.expanded], "cast heal all", "new command is sent")

B(2):fireClick() -- an empty button: click opens the editor too
eq(count_("rmgui.custom.editor") > 0, true, "click on an empty button opens the editor")
eq(E("name").typed, "", "empty editor")
E("command"):print("look"); E("name"):print("")
E("command"):enter() -- Enter in a field saves
eq(B(2).text, "look", "no name: label taken from the command"); eq(env.settings.custom[2].command, "look", "saved by Enter")
eq(count_("rmgui.custom.editor"), 0, "editor closed after Enter")

B(3):fireRightClick(); E("name"):print("x"); E("command"):print("")
E("save"):fireClick()
eq(said[#said], "the command is empty", "name without command is refused")
eq(B(3).text, "+", "refused: button unchanged")
eq(count_("rmgui.custom.editor") > 0, true, "refused: editor stays open")
E("cancel"):fireClick()
eq(count_("rmgui.custom.editor"), 0, "cancel closes"); eq(env.settings.custom[3], nil, "cancel stores nothing")

B(1):fireRightClick(); E("clear"):fireClick()
eq(B(1).text, "+", "clear empties the button"); eq(#env.settings.custom, 1, "only slot 2 left in the settings")
B(2):fireRightClick(); B(4):fireRightClick()
eq(count_("rmgui.custom.editor.save"), 1, "opening a second editor replaces the first")

---------------------------------------------------------------- theme change and layout
theme(); eq(count_("rmgui.custom.editor"), 0, "a theme change closes the editor"); eq(B(2).text, "look", "buttons redrawn")
F.fire("rmgui.onLayout", { layout = "wide" })
eq(count_("rmgui.custom.button."), 12, "onLayout builds nothing twice")
local old = slot
slot = Geyser.Container:new({ name = "slot2", x = 0, y = 0, width = 400, height = 108 })
old:delete()
F.fire("rmgui.onLayout", { layout = "wide" })
eq(count_("rmgui.custom.button."), 12, "rebuilt in the replaced slot"); eq(B(2).parent, slot, "new parent")
eq(B(2).text, "look", "state survives a rebuild")

---------------------------------------------------------------- failures
F.failOn = { ["Label:echo"] = true }
eq(pcall(theme), true, "failing echo does not raise")
F.failOn = { ["Label:setClickCallback"] = true }
eq(pcall(function() rmgui.custom.init(env) end), true, "failing setClickCallback does not raise")
F.failOn = nil
env.expandAlias = function() error("boom") end
rmgui.custom.init(env); theme()
eq(pcall(function() B(2):fireClick() end), true, "a failing send does not raise")
eq(said[#said]:find("send:", 1, true) ~= nil, true, "failing send reported")
F.failOn = { ["CommandLine:new"] = true }
eq(pcall(function() B(2):fireRightClick() end), true, "failing CommandLine does not raise")
F.failOn = nil
rmgui.custom.teardown()
eq(count_("rmgui.custom"), 0, "nothing left after a failed editor")

---------------------------------------------------------------- no slot, teardown, re-init
env = world({ noSlot = true }); rmgui.custom.init(env)
eq(count_("rmgui.custom"), 0, "no slot: no buttons")
rmgui.layout = { get = function() return slot end }
F.fire("rmgui.onLayout", {}); eq(count_("rmgui.custom.button."), 12, "onLayout builds late")
rmgui.custom.teardown(); rmgui.custom.teardown()
eq(count_("rmgui.custom"), 0, "teardown removes the buttons"); eq(elements["custom.buttons"], nil, "theme element removed")
eq(#F.handlers, 0, "no handler left")
rmgui.custom.init(env); rmgui.custom.init(env)
eq(count_("rmgui.custom.button."), 12, "init twice: still twelve"); eq(#F.handlers, 1, "init twice: one handler")
rmgui.custom.teardown()
eq(pcall(rmgui.custom.init, nil), true, "init without env")

print(("custom_glue: %d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
