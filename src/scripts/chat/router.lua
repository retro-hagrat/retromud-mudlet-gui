-- chat/router: pure Lua. Which tabs a message goes to, and the channel prefix per tab (CHAT-020, 023, 024).
rmgui = rmgui or {}
rmgui.chat = rmgui.chat or {}
local C = rmgui.chat

C.TABS = {
    { id = "all", title = "All" },
    { id = "chat", title = "Chat" },
    { id = "world", title = "World" },
    { id = "party", title = "Party" },
    { id = "info", title = "Info" },
    { id = "wizard", title = "Wizard", lazy = true }, -- CHAT-025
    { id = "guild", title = "Guild" },
    { id = "tells", title = "Tells" },
}

local OWN = { chat = "chat", world = "world", party = "party", info = "info", alert = "info",
              wizard = "wizard", guild = "guild", tells = "tells" }

function C.tabsFor(msg)
    local own = type(msg) == "table" and OWN[msg.group]
    if own then return { "all", own } end
    return { "all" }
end

-- party and tells are one channel each, so the channel name adds nothing there
function C.prefixFor(msg, tabId)
    if tabId == "party" or tabId == "tells" then return "" end
    if tabId == "all" or OWN[msg.group] == tabId then return "[" .. tostring(msg.channel) .. "] " end
    return ""
end
