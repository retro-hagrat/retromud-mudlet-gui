-- chat/engine: pure Lua line classifier. No Mudlet or Geyser calls.
-- feed(line, isPrompt) returns the message that this line completed, or nil.
-- A message is complete when a line arrives that does not continue it.
-- Call flush() at the end of the input.
rmgui = rmgui or {}
rmgui.chat = rmgui.chat or {}
local C = rmgui.chat

-- Any opener may close with ] } or >: the game prints [retro} as well as [retro].
local OPEN = { ["["] = true, ["{"] = true, ["<"] = true }
local CLOSE = { ["]"] = true, ["}"] = true, [">"] = true }
local SHOUT_MAX_LINES = 4 -- an unclosed shout must not swallow the lines after it

local function msg(form, channel, group, speaker, rank, text, line)
    return { form = form, channel = channel, group = group, speaker = speaker,
             rank = rank, parts = { text }, lines = { line } }
end

-- Decorations sorted longest first, so a longer one wins over a prefix of it.
local function sortedDecorations(rules)
    local list = {}
    for text, channel in pairs(rules.decorations) do list[#list + 1] = { text = text, channel = channel } end
    table.sort(list, function(a, b) return #a.text > #b.text end)
    return list
end

-- rest starts with a decoration followed by "> text". Plain compare (CHAT-014).
local function decoration(list, rest)
    for _, d in ipairs(list) do
        if rest:sub(1, #d.text) == d.text then
            local body = rest:sub(#d.text + 1):match("^%s*> ?(.*)$")
            if body then return d.channel, body end
        end
    end
end

-- An unknown decoration must look like one: 3+ characters with a symbol.
-- That keeps plain text such as "a < b > c" out of the Guild tab.
local function unknownGuild(rest)
    local dec, body = rest:match("^(%S.-)%s+> (.*)$")
    if dec and #dec >= 3 and dec:find("%p") then return "guild", body end
end

-- Some guilds print no angle brackets: "Shane __[Jomsviking]__) what?"
local function bareGuild(list, line)
    local speaker, rest = line:match("^(%a[%w'%-]*)%s+(%S.*)$")
    if not speaker or not rest then return end
    for _, d in ipairs(list) do
        if rest:sub(1, #d.text) == d.text then
            local body = rest:sub(#d.text + 1):match("^%s*(.*)$")
            if body and body ~= "" then return speaker, d.channel, body end
        end
    end
end

local function guild(list, line)
    if line:sub(1, 2) == "< " then -- action form: < decoration > Name text
        local rest = line:sub(3)
        local channel, body = decoration(list, rest)
        if not channel then
            channel, body = unknownGuild(rest)
            if not channel then return end
        end
        return msg("guild-action", channel, "guild", nil, nil, body, line)
    end
    local p = line:find(" < ", 1, true)
    if p and line:sub(1, 1):match("%a") and p <= 61 then
        local speaker, rest = line:sub(1, p - 1), line:sub(p + 3)
        local channel, body = decoration(list, rest)
        if not channel then
            channel, body = unknownGuild(rest) -- CHAT-004: still lands on the Guild tab
        end
        if channel then return msg("guild", channel, "guild", speaker, nil, body, line) end
    end
    local speaker, channel, body = bareGuild(list, line)
    if speaker then return msg("guild", channel, "guild", speaker, nil, body, line) end
end

local function classify(R, list, line)
    local f, who, text = R.forms
    who, text = line:match(f.tell)
    if who then return msg("tell", "tell", "tells", who, nil, text, line) end
    local m = guild(list, line)
    if m then return m end
    who, text = line:match(f.party)
    if who then return msg("party", "party", "party", who, nil, text, line) end
    local sp, o, name, c, body = line:match(f.player)
    if sp and OPEN[o] and CLOSE[c] and R.channels[name] then
        return msg("channel", name, R.channels[name], sp, o .. c, body, line)
    end
    o, name, c, body = line:match(f.action)
    if o and OPEN[o] and CLOSE[c] and R.channels[name] then
        -- the name and the action cannot be split safely, so the speaker is nil
        return msg("action", name, R.channels[name], nil, o .. c, body, line)
    end
    name, body = line:match(f.system)
    if name and R.channels[name] then
        return msg("system", name, R.channels[name], nil, nil, body, line)
    end
    -- Eros shouts, 'text'  and  You shout, 'text'. The closing quote may be on a later line.
    who, text = line:match("^(%a[%w'%-]*) shouts?, '(.*)$")
    if who then return msg("shout", "shout", "info", who, nil, text, line) end
end

local function isContinuation(R, line)
    local c = R.continuation
    local sp, body = line:match("^( +)(%S.*)$")
    if not sp or #sp < c.min or #sp > c.max then return false end
    local _, alnum = body:gsub("%w", "")
    local _, nonspace = body:gsub("%S", "")
    return alnum / nonspace >= c.minWordRatio -- rejects ASCII art
end

-- A shout stays open until a line ends with the closing quote, so a wrap like
-- "matchmaking on" / "Sosel!'" stays one message even when the next line is not indented.
-- It ends at once if the next line is a message of its own, and after SHOUT_MAX_LINES.
local function shoutOpen(R, list, m, line)
    if m.form ~= "shout" or #m.parts >= SHOUT_MAX_LINES then return false end
    if (m.parts[#m.parts] or ""):sub(-1) == "'" then return false end
    return classify(R, list, line) == nil
end

local function finish(m)
    local text = table.concat(m.parts, " ")
    if m.form == "tell" or m.form == "shout" then text = text:gsub("'%s*$", "") end
    m.text, m.parts = text, nil
    return m
end

function C.newEngine(rules)
    local R = rules or C.rules
    local list = sortedDecorations(R)
    local e = { pending = nil, history = false }

    function e:flush()
        local m = self.pending
        self.pending = nil
        return m and finish(m)
    end

    function e:feed(line, isPrompt)
        if self.history then -- CHAT-070, CHAT-071: history stays in the main window
            if isPrompt then self.history = false end
            return nil
        end
        if isPrompt or line:match("^%s*$") then return self:flush() end
        local p = self.pending
        if p and (isContinuation(R, line) or shoutOpen(R, list, p, line)) then
            p.parts[#p.parts + 1] = line:match("^%s*(.-)%s*$")
            p.lines[#p.lines + 1] = line
            return nil
        end
        local done = self:flush()
        if line:match(R.forms.history) then
            self.history = true
            return done
        end
        local t = line:match(R.forms.time)
        local m = classify(R, list, t and line:sub(#t + 1) or line)
        if m and t then m.time = t:match("%d+:%d+:%d+") end
        self.pending = m
        return done
    end

    return e
end
