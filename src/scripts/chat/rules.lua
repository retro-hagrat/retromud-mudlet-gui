-- chat/rules: routing data for the chat engine. No logic here (CHAT-010).
rmgui = rmgui or {}
rmgui.chat = rmgui.chat or {}

rmgui.chat.rules = {
    -- Lua patterns for the line forms (doc/spec/chat.md CHAT-002).
    forms = {
        tell = "^(.-) telepathically contacts you with '(.*)$",
        party = "^(.-) %(Party%): ?(.*)$",
        player = "^(.-) ([%[{<])(%a+)([%]}>]): ?(.*)$", -- Name [chan]: text
        action = "^([%[{<])(%a+)([%]}>]): ?(.*)$",      -- <chan>: Name action
        system = "^%[(%a+)%] (.*)$",                    -- [info] text, [welstar] text
        history = "^Displaying last %a+:$",
        time = "^%[%d+%] %[%d+:%d+:%d+%] ",             -- history prefix (CHAT-072)
    },
    -- Continuation lines of a wrapped message. shortcut: indent range and
    -- letter ratio come from 11 sample logs at width 80; widen them if a
    -- player reports a message that breaks in two.
    continuation = { min = 5, max = 7, minWordRatio = 0.5 },
    -- Channel name -> group. Names outside this table are never chat (CHAT-001).
    channels = {
        chat = "chat", retro = "chat", sales = "chat", mentor = "chat",
        welstar = "world", wysoom = "world", raji = "world",
        sosel = "world", crypt = "world", perdow = "world",
        wiz = "wizard", arch = "wizard",
        info = "info", inform = "info", alert = "alert",
    },
    -- Guild decorations, without spaces at the ends (CHAT-012, CHAT-015).
    decorations = {
        ["^abjurer^"] = "abjurer", ["[alchemist]:"] = "alchemist",
        ["-Assassin-"] = "assassin", ["[BARD] [===]---#"] = "bard",
        ["<>biomancer<>:"] = "biomancer", ["(Cultist):"] = "cultist",
        ["',~~ DRUID ~~,'"] = "druid", ["(FALLEN) =}----"] = "fallen",
        ["(=Fighter=)"] = "fighter", ["__[Jomsviking]__)"] = "jomsviking",
        ["$$ MERCHANT $$ :"] = "merchant", ["69 MONK 69:"] = "monk",
        ["{Paladin}"] = "paladin", ["{Psionicist}"] = "psionicist",
        [">>-RANGER->"] = "ranger", ["[TEMPLAR]:"] = "templar",
    },
}
