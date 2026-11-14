-- retromud-gui: Geyser UI. Talks to the standalone mapper package only via events.
rmgui = rmgui or {}
local NAME = "retromud-gui"

local function mapperVersion()
  local v = getPackageInfo and getPackageInfo("retromud", "version")
  return v ~= "" and v or nil
end

function rmgui.build()
  rmgui.top = Adjustable.Container:new({
    name = "rmgui.top", x = 0, y = 0, width = "100%", height = 30,
    titleText = "RetroMUD",
  })
  rmgui.status = Geyser.Label:new({
    name = "rmgui.status", x = 0, y = 0, width = "100%", height = "100%",
  }, rmgui.top)
  rmgui.status:setStyleSheet("background-color: #1b1b1b; color: #ddd; padding-left: 6px;")
  rmgui.setRoom(nil)
  setBorderTop(30)
end

function rmgui.setRoom(name)
  local mapper = mapperVersion() and "" or " (mapper not installed)"
  rmgui.status:echo((name or "no room yet") .. mapper)
end

function rmgui.teardown()
  setBorderTop(0)
  if rmgui.top then rmgui.top:hide() end
  for _, id in ipairs(rmgui.handlers or {}) do killAnonymousEventHandler(id) end
  rmgui.handlers = nil
end

function rmgui.start()
  rmgui.teardown()
  rmgui.build()
  rmgui.handlers = {
    -- rm.onRoom is raised by the mapper package (retromud-mudlet-mapper)
    registerAnonymousEventHandler("rm.onRoom", function(_, room) rmgui.setRoom(room.name) end),
    registerAnonymousEventHandler("sysUninstallPackage", function(_, pkg)
      if pkg == NAME then rmgui.teardown() end
    end),
  }
end

rmgui.start()
