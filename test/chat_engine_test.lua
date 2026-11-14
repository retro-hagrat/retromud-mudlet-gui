-- Tests for src/scripts/chat. Run from the repo root: lua test/chat_engine_test.lua
-- All names and text below are made up. COVER=1 prints engine lines that no test ran.
local root = (arg[0]:match("^(.*)/test/[^/]*$")) or "."
local COVER = os.getenv("COVER")
local hit = {}
if COVER then
    debug.sethook(function(_, l) hit[debug.getinfo(2, "S").short_src .. ":" .. l] = true end, "l")
end
dofile(root .. "/src/scripts/chat/rules.lua")
dofile(root .. "/src/scripts/chat/engine.lua")
local C = rmgui.chat

local fails, count = 0, 0
local function eq(got, want, label)
    count = count + 1
    if got ~= want then
        fails = fails + 1
        print(("FAIL %s\n   got:  %s\n   want: %s"):format(label, tostring(got), tostring(want)))
    end
end

-- Feed lines like the game does. A line that starts with "Hp:" is a prompt.
local function run(lines, engine)
    local e, out = engine or C.newEngine(), {}
    for _, l in ipairs(lines) do
        local m = e:feed(l, l:match("^Hp:%d") ~= nil)
        if m then out[#out + 1] = m end
    end
    local m = e:flush()
    if m then out[#out + 1] = m end
    return out
end
local PROMPT = "Hp:120/120 Sp:80/95 Ep:60/60 Exp:5000 >"

local function one(lines, label)
    local out = run(lines)
    eq(#out, 1, label .. ": one message")
    return out[1] or {}
end

---------------------------------------------------------------- single lines
local m = one({ "Aldric [retro]: hello there" }, "player channel")
eq(m.form, "channel", "player form"); eq(m.channel, "retro", "player channel")
eq(m.group, "chat", "player group"); eq(m.speaker, "Aldric", "player speaker")
eq(m.rank, "[]", "player rank"); eq(m.text, "hello there", "player text")

m = one({ "Mirel {sales}: wts a sword" }, "curly rank")
eq(m.rank, "{}", "curly rank"); eq(m.channel, "sales", "curly channel")
m = one({ "Bran <mentor>: ask me anything" }, "angle rank")
eq(m.rank, "<>", "angle rank"); eq(m.group, "chat", "mentor group")
m = one({ "Karo, Maker of Odd Things <chat>: hi" }, "long speaker")
eq(m.speaker, "Karo, Maker of Odd Things", "speaker with title and comma")
m = one({ "Aldric [chat]:" }, "empty text")
eq(m.text, "", "empty text")

m = one({ "<retro>: Bran waves" }, "action angle")
eq(m.form, "action", "action form"); eq(m.speaker, nil, "action speaker is nil")
eq(m.text, "Bran waves", "action text"); eq(m.channel, "retro", "action channel")
m = one({ "{retro}: Aldric waves" }, "action curly"); eq(m.rank, "{}", "action curly rank")
m = one({ "[sales]: Mirel waves" }, "action square"); eq(m.rank, "[]", "action square rank")

m = one({ "Mirel telepathically contacts you with 'see you soon.'" }, "tell")
eq(m.form, "tell", "tell form"); eq(m.group, "tells", "tell group")
eq(m.speaker, "Mirel", "tell speaker"); eq(m.text, "see you soon.", "tell text, quote removed")
m = one({ "Mirel telepathically contacts you with 'it's fine'" }, "tell inner quote")
eq(m.text, "it's fine", "tell keeps inner quote")

m = one({ "Aldric (Party): ready" }, "party")
eq(m.group, "party", "party group"); eq(m.speaker, "Aldric", "party speaker")

m = one({ "[info] Aldric goes linkdead" }, "info")
eq(m.form, "system", "info form"); eq(m.group, "info", "info group"); eq(m.speaker, nil, "info speaker nil")
m = one({ "[info] The old tower bell rings." }, "info no name")
eq(m.speaker, nil, "info without a name has no speaker"); eq(m.text, "The old tower bell rings.", "info text")
m = one({ "[alert] The gate is closing." }, "alert"); eq(m.group, "alert", "alert group")
m = one({ "[welstar] A horn sounds." }, "world"); eq(m.group, "world", "world group"); eq(m.channel, "welstar", "world channel")
for _, w in ipairs({ "welstar", "wysoom", "raji", "sosel", "crypt", "perdow" }) do
    m = one({ "[" .. w .. "] news" }, "world " .. w); eq(m.group, "world", "world group " .. w)
end
m = one({ "Aldric <wiz>: test" }, "wiz"); eq(m.group, "wizard", "wiz group")
m = one({ "Aldric <arch>: test" }, "arch"); eq(m.group, "wizard", "arch group")

---------------------------------------------------------------- guild lines
local guilds = {
    abjurer = "^abjurer^", alchemist = "[alchemist]:", assassin = "-Assassin-",
    bard = "[BARD] [===]---#", biomancer = "<>biomancer<>:", cultist = "(Cultist):",
    druid = "',~~ DRUID ~~,'", fallen = "(FALLEN) =}----", fighter = "(=Fighter=)",
    jomsviking = "__[Jomsviking]__)", merchant = "$$ MERCHANT $$ :", monk = "69 MONK 69:",
    paladin = "{Paladin}", psionicist = "{Psionicist}", ranger = ">>-RANGER->", templar = "[TEMPLAR]:",
}
for channel, dec in pairs(guilds) do
    m = one({ "Aldric < " .. dec .. " > one two three" }, "guild " .. channel)
    eq(m.channel, channel, "guild channel " .. channel); eq(m.group, "guild", "guild group " .. channel)
    eq(m.speaker, "Aldric", "guild speaker " .. channel); eq(m.text, "one two three", "guild text " .. channel)
    m = one({ "Aldric < " .. dec .. "  > two spaces" }, "guild 2sp " .. channel)
    eq(m.channel, channel, "guild with two spaces " .. channel); eq(m.text, "two spaces", "two-space text " .. channel)
    m = one({ "< " .. dec .. " > Aldric waves" }, "guild action " .. channel)
    eq(m.form, "guild-action", "guild action form " .. channel); eq(m.channel, channel, "guild action channel " .. channel)
    eq(m.speaker, nil, "guild action speaker nil " .. channel); eq(m.text, "Aldric waves", "guild action text " .. channel)
end
m = one({ "Aldric < (NEWGUILD) > hi" }, "unknown guild")
eq(m.channel, "guild", "unknown decoration lands on Guild"); eq(m.group, "guild", "unknown group"); eq(m.text, "hi", "unknown text")
m = one({ "< (NEWGUILD) > Aldric waves" }, "unknown guild action"); eq(m.group, "guild", "unknown action group")
eq(#run({ "x < 5 > y" }), 0, "plain text with numbers is not a guild line")
eq(#run({ "Aldric < ab > hi" }), 0, "short unknown decoration is not a guild line")
eq(#run({ "Aldric < some words > hi" }), 0, "unknown decoration without a symbol is not a guild line")
eq(#run({ "< some words > Aldric waves" }), 0, "unknown action decoration without a symbol")
m = one({ "Aldric < " .. "(=Fighter=)" .. " >" }, "guild empty text"); eq(m.text, "", "guild empty text")

---------------------------------------------------------------- not chat
for _, l in ipairs({
    "You [hit]: 120", "Aldric [hits]: 5", "[beating] labeled TEST.", "Aldric says 'hello'",
    "Aldric (Fake): x", "The room is dark.", "Aldric [retro] no colon", "Aldric {retro): mismatched",
    "<hit>: Aldric waves", "[hit] something", "a < b > c", "Nothing to show.",
    PROMPT, "", "   ", "Aldric < no closing bracket",
}) do
    eq(#run({ l }), 0, "not chat: " .. l)
end
eq(#run({ "Aldric {retro): mismatched" }), 0, "mismatched brackets")

---------------------------------------------------------------- multi-line
local function ml(first, conts, label, want)
    local lines = { first }
    for _, c in ipairs(conts) do lines[#lines + 1] = c end
    local out = run(lines)
    eq(#out, 1, label .. ": one message")
    eq(out[1] and out[1].text, want, label .. ": joined text")
    eq(out[1] and #out[1].lines, #lines, label .. ": raw line count")
    return out[1] or {}
end

-- two lines, normal 6-space indent
ml("Aldric [retro]: the first part of a message that is long enough to wrap onto",
   { "      a second line." }, "player 2 lines",
   "the first part of a message that is long enough to wrap onto a second line.")
-- three and five lines
ml("Aldric [mentor]: one two three four five six seven eight nine ten eleven",
   { "      twelve thirteen fourteen fifteen sixteen seventeen eighteen", "      nineteen twenty." },
   "player 3 lines", "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.")
local many = {}
for i = 1, 9 do many[i] = "      part" .. i end
m = ml("Aldric [chat]: start", many, "ten lines", "start part1 part2 part3 part4 part5 part6 part7 part8 part9")
-- indent variants: 5 and 7 spaces (seen in real logs), 6 is the norm
ml("Aldric [retro]: short first line", { "     stats" }, "indent 5", "short first line stats")
ml("Aldric [retro]: short first line", { "       stats" }, "indent 7", "short first line stats")
ml("[info] Aldric enters the game.", { "       (19 players)" }, "info 7-space", "Aldric enters the game. (19 players)")
-- indent outside 5..7 is not a continuation
for _, w in ipairs({ 0, 1, 2, 3, 4, 8, 12, 19 }) do
    local out = run({ "Aldric [retro]: first line", string.rep(" ", w) .. "second line" })
    eq(#out, 1, "indent " .. w .. " not continuation")
    eq(out[1] and #out[1].lines, 1, "indent " .. w .. " keeps one line")
end
-- ASCII art after a message is not part of it (indent 5-7, few letters)
m = ml("Aldric [retro]: a map follows", { "      and more text" }, "art after message", "a map follows and more text")
local art = run({ "Aldric [retro]: a map follows", "       ~~~~~~~~~~~~~~~~~~~~~       ",
                  "     ~~~~~~~~~~~~~~~~~~~~~~~~~     ", "      ccccc..................cccc~~   " })
eq(#art, 1, "art: one message"); eq(art[1].text, "a map follows", "art not joined"); eq(#art[1].lines, 1, "art lines")
-- tell with quotes and a hyphen inside, over three lines
m = ml("Mirel telepathically contacts you with 'At the very least, it ought to be",
       { '      possible to have a script that runs through stuff like "prompt" to copy', "      what players asked of the game - should that be an issue.'" },
       "tell 3 lines", 'At the very least, it ought to be possible to have a script that runs through stuff like "prompt" to copy what players asked of the game - should that be an issue.')
eq(m.form, "tell", "tell multi form"); eq(m.speaker, "Mirel", "tell multi speaker")
-- guild, action, party, world, system, wizard multi-line
m = ml("Aldric < [BARD] [===]---#  > this is a longer message that wraps onto", { "      a second line" }, "guild 2 lines", "this is a longer message that wraps onto a second line")
eq(m.channel, "bard", "guild multi channel")
m = ml("< ^abjurer^ > Aldric waves and then does something that wraps", { "      to the next line" }, "guild action 2 lines", "Aldric waves and then does something that wraps to the next line")
m = ml("<retro>: Bran does a very long thing that wraps", { "      to the next line" }, "action 2 lines", "Bran does a very long thing that wraps to the next line")
m = ml("Aldric (Party): a long party message that wraps", { "      onto a second line" }, "party 2 lines", "a long party message that wraps onto a second line")
m = ml("[welstar] A loud horn sounds across the", { "      world as a great beast falls!" }, "world 2 lines", "A loud horn sounds across the world as a great beast falls!")
m = ml("Aldric <wiz>: a wizard message that wraps", { "      onto a second line" }, "wiz 2 lines", "a wizard message that wraps onto a second line")
-- tabs or trailing spaces on a continuation line are trimmed
ml("Aldric [retro]: first", { "      second   " }, "trailing spaces", "first second")

-- what ends a message
local out = run({ "Aldric [retro]: first message", "      continued", "Mirel [retro]: second message", "      continued too" })
eq(#out, 2, "two messages back to back"); eq(out[1].text, "first message continued", "first joined")
eq(out[2].text, "second message continued too", "second joined"); eq(out[1].speaker, "Aldric", "first speaker")
out = run({ "Aldric [retro]: first", "", "      stray indent line" })
eq(#out, 1, "blank line ends a message"); eq(out[1].text, "first", "blank line: text")
out = run({ "Aldric [retro]: first", PROMPT, "      stray indent line" })
eq(#out, 1, "prompt ends a message"); eq(out[1].text, "first", "prompt: text")
out = run({ "Aldric [retro]: first", "The room is dark.", "      stray indent line" })
eq(#out, 1, "plain text ends a message"); eq(out[1].text, "first", "plain text: text")
out = run({ "      indented line with no parent", "      another" })
eq(#out, 0, "continuation without a message is ignored")
out = run({ "The room is dark.", "      indented room text" })
eq(#out, 0, "indent after non-chat is ignored")
-- chat lines between other output, no blank lines (CHAT-005)
out = run({ "A cat walks in.", "Aldric [retro]: hi", "The cat leaves.", "[info] Mirel goes linkdead", "Bran leaves east." })
eq(#out, 2, "chat between other output"); eq(out[1].text, "hi", "first between"); eq(out[2].text, "Mirel goes linkdead", "second between")
-- the prompt line with the typed command after it is not chat (CHAT-006)
out = run({ PROMPT .. "retro say hello", "Aldric [retro]: hello" })
eq(#out, 1, "typed command after prompt is ignored"); eq(out[1].text, "hello", "typed command: text")
-- the message is returned by the NEXT line, or by flush
local e = C.newEngine()
eq(e:feed("Aldric [retro]: hi", false), nil, "feed holds the pending message")
eq(e:feed("      more", false), nil, "continuation is held")
eq(e:feed(PROMPT, true).text, "hi more", "prompt completes the message")
eq(e:flush(), nil, "flush with nothing pending")
e:feed("Aldric [retro]: last", false)
eq(e:flush().text, "last", "flush returns pending"); eq(e:flush(), nil, "flush twice")

---------------------------------------------------------------- history
out = run({ "Displaying last retro:",
    "[1700000200] [10:16:40] Aldric {retro}: one two three",
    "[1700000210] [10:16:50] Mirel [retro]: four five six",
    "seven eight nine", PROMPT, "Aldric [retro]: live line" })
eq(#out, 1, "history lines are not routed"); eq(out[1].text, "live line", "live line after history")
out = run({ "Displaying last wiz:", "[1700000100] [10:15:00] Aldric <wiz>: test", "wrapped with no indent", PROMPT })
eq(#out, 0, "wiz history is not routed")
out = run({ "Aldric [retro]: live", "Displaying last retro:", "[1700000200] [10:16:40] Aldric {retro}: old", PROMPT })
eq(#out, 1, "message before a history header is kept"); eq(out[1].text, "live", "live before history")
out = run({ "Displaying last retro:", PROMPT, "Aldric [retro]: after" })
eq(#out, 1, "empty history block ends at the prompt")
-- a timestamp prefix on a live line is removed and kept (CHAT-072)
m = one({ "[1700000200] [10:16:40] Aldric [retro]: stamped" }, "timestamp")
eq(m.speaker, "Aldric", "timestamp: speaker"); eq(m.time, "10:16:40", "timestamp: time"); eq(m.text, "stamped", "timestamp: text")

---------------------------------------------------------------- engine isolation
local e1, e2 = C.newEngine(), C.newEngine()
e1:feed("Aldric [retro]: only in e1", false)
eq(e2:flush(), nil, "engines do not share state")
-- custom rules: a new channel needs only a table entry (CHAT-010)
local rules = {}
for k, v in pairs(C.rules) do rules[k] = v end
rules.channels = { newchan = "chat" }
out = run({ "Aldric [newchan]: hi", "Aldric [retro]: hi" }, C.newEngine(rules))
eq(#out, 1, "custom channel table"); eq(out[1].channel, "newchan", "custom channel")

---------------------------------------------------------------- speed (CHAT-060)
local sample = { "Aldric [retro]: hello there", "      and more", "Aldric < (=Fighter=) > hi", "The room is dark.",
    "[info] Bran sleeps", "Mirel telepathically contacts you with 'hi'", PROMPT }
local big = {}
for i = 1, 60000 do big[i] = sample[(i - 1) % #sample + 1] end
local t0 = os.clock()
local e = C.newEngine()
for _, l in ipairs(big) do e:feed(l, l:match("^Hp:%d") ~= nil) end
local per = (os.clock() - t0) / #big * 1000
eq(per < 1, true, ("speed under 1 ms per line (%.4f ms)"):format(per))

if COVER then
    debug.sethook()
    for _, f in ipairs({ "engine.lua", "rules.lua" }) do
        local path = root .. "/src/scripts/chat/" .. f
        local n = 0
        for l in io.lines(path) do
            n = n + 1
            local code = l:match("^%s*(.-)%s*$")
            local skip = code == "" or code:match("^%-%-") or code:match("^end[%),]*$") or code:match("^else$")
                or code:match("^[%]})]+,?$") or code:match("^local function") or code:match("^function ") or code:match("^}$")
            if not skip and not hit[path .. ":" .. n] and not hit[("%s:%d"):format(path, n)] then
                print(("not run  %s:%d  %s"):format(f, n, code))
            end
        end
    end
end

print(("%d checks, %d failed"):format(count, fails))
os.exit(fails == 0 and 0 or 1)
