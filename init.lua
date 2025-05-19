--  CONFIG  ------------------------------------------------
------------------------------------------------------------
local hs_app = require "hs.application"
local hs_eventtap = require "hs.eventtap"
local hs_keycodes = require "hs.keycodes"
local hs_hotkey = require "hs.hotkey"
local hs_alert = require "hs.alert"
local hs_fnutils = require "hs.fnutils"
local hs_logger = require "hs.logger"

-- Ensure our global table for taps exists
_G.myActiveTaps = _G.myActiveTaps or {}

-- apps where we *never* want Ctrl→Cmd remaps  (BUNDLE-IDs)
local REMAP_BLOCKED_APPS = {
  ["com.apple.Terminal"]      = true,
  ["com.googlecode.iterm2"]   = true,
  ["com.jetbrains.intellij"]  = true,
  ["com.jetbrains.goland"]    = true,
  ["com.jetbrains.pycharm"]   = true,
  ["com.jetbrains.rider"]     = true,
  ["com.jetbrains.WebStorm"]  = true,
  ["com.jetbrains.datagrip"]  = true,
  ["com.jetbrains.clion"]     = true,
  ["com.jetbrains.rustrover"] = true,
  ["com.microsoft.VSCode"]    = true,
}

-- apps where we want to block Ctrl+Cmd+F (fullscreen)  (BUNDLE-IDs)
local FULLSCREEN_BLOCKED_APPS = {
  ["com.apple.Terminal"]     = true,
  ["com.googlecode.iterm2"]  = true,
  ["com.jetbrains.intellij"] = true,
  ["com.microsoft.VSCode"]   = true,
  ["com.sublimetext.4"]      = true,
  ["com.apple.dt.Xcode"]     = true,
}

-- global shortcuts, checked first and bypass REMAP_BLOCKED_APPS
local GLOBAL_SHORTCUTS = {
  {
    mods = { "cmd", "shift" },
    key = "down",
    action = function(event, eventIsKeyDown, appName, bundleID)
      if eventIsKeyDown then -- Only act on key down
        logKeyEvent(event, "remapTap: GLOBAL Action: Minimize Window (Cmd+Shift+Down -> Cmd+M)", appName, bundleID)
        hs_eventtap.keyStroke({ "cmd" }, "m", 0)
      end
      -- The event is consumed by returning true in the main remapTap loop after this action is called.
    end,
    description = "Minimize Window (Cmd+Shift+Down -> Cmd+M)"
  },
  {
    mods = { "ctrl" },
    key = "left",
    sendMods = { "alt" },
    keyOut = "left",
    description = "Ctrl+Left -> Alt+Left (Word Left)"
  },
  {
    mods = { "ctrl" },
    key = "right",
    sendMods = { "alt" },
    keyOut = "right",
    description = "Ctrl+Right -> Alt+Right (Word Right)"
  },
}

-- declarative shortcut map (general remaps)
local SHORTCUTS = {
  { mods = { "ctrl" },      key = "c",           sendMods = { "cmd" },      keyOut = "c" },
  { mods = { "ctrl" },      key = "d",           sendMods = { "cmd" },      keyOut = "d" },
  { mods = { "ctrl" },      key = "n",           sendMods = { "cmd" },      keyOut = "n" },
  { mods = { "ctrl" },      key = "v",           sendMods = { "cmd" },      keyOut = "v" },
  { mods = { "ctrl" },      key = "x",           sendMods = { "cmd" },      keyOut = "x" },
  { mods = { "ctrl" },      key = "z",           sendMods = { "cmd" },      keyOut = "z" },
  { mods = { "ctrl" },      key = "a",           sendMods = { "cmd" },      keyOut = "a" },
  { mods = { "ctrl" },      key = "s",           sendMods = { "cmd" },      keyOut = "s" },
  { mods = { "ctrl" },      key = "p",           sendMods = { "cmd" },      keyOut = "p" },
  { mods = { "ctrl" },      key = "f",           sendMods = { "cmd" },      keyOut = "f" },
  { mods = { "ctrl" },      key = "t",           sendMods = { "cmd" },      keyOut = "t" },
  { mods = { "ctrl" },      key = "w",           sendMods = { "cmd" },      keyOut = "w" },
  { mods = { "ctrl" },      key = "return",      sendMods = { "cmd" },      keyOut = "return" },
  { mods = { "ctrl" },      key = "enter",       sendMods = { "cmd" },      keyOut = "return" },                -- 'enter' is often the same as 'return'
  { mods = { "ctrl" },      key = "y",           sendMods = { "cmd", "shift" }, keyOut = "z" },                 -- Redo
  { mods = { "ctrl" },      key = "forwarddelete", sendMods = { "alt" },    keyOut = "forwarddelete" },
  { mods = { "ctrl" },      key = "delete",      sendMods = { "alt" },      keyOut = "delete" },
  { mods = { "ctrl" },      key = "r",           sendMods = { "cmd" },      keyOut = "r" },

  { mods = { "ctrl", "shift" }, key = "r",       sendMods = { "cmd", "shift" }, keyOut = "r" },
  { mods = { "ctrl", "shift" }, key = "e",       sendMods = { "cmd", "alt" }, keyOut = "e" },
  { mods = { "ctrl", "shift" }, key = "c",       sendMods = { "cmd", "alt" }, keyOut = "c" },
  { mods = { "ctrl", "shift" }, key = "k",       sendMods = { "cmd", "alt" }, keyOut = "k" },

  { mods = { "ctrl" },      scroll = "up",       sendMods = { "cmd" },      keyOut = "+" },                -- Zoom in
  { mods = { "ctrl" },      scroll = "down",     sendMods = { "cmd" },      keyOut = "-" },                -- Zoom out

  { mods = { "ctrl", "alt" }, key = "¨",         sendMods = { "alt" },      keyOut = "¨" },                -- Example, adjust key as needed for your layout
  { mods = { "ctrl", "alt" }, key = "down",      sendMods = { "cmd" },      keyOut = "-" },                -- Example, might conflict with scroll

  { mods = { "ctrl", "shift" }, key = "b",       sendMods = { "cmd", "shift" }, keyOut = "b" },
}

-- app specific launchers
local APP_SHORTCUTS = {
  { mods = { "ctrl", "alt" }, key = "delete", app = "Activity Monitor" },
  { mods = { "ctrl", "shift" }, key = "escape", app = "Activity Monitor" },
}

------------------------------------------------------------
--  DEBUG LOGGER  -----------------------------------------
------------------------------------------------------------
local DEBUG = true -- Set to true for debug output, false to disable

local keyEventsLogger
if DEBUG then
  keyEventsLogger = hs_logger.new('keyEvents', 'debug')
else
  -- Provide a noop object, so calls don't error
  keyEventsLogger = { d = function() end }
end

local function logKeyEvent(e, message, appName, bundleID)
  local flags = e:getFlags()
  local keyCode = e:getKeyCode()
  local keyStr = hs_keycodes.map[keyCode] or "UNMAPPED:" .. tostring(keyCode)

  keyEventsLogger:d(string.format(
    "%s (App: %s [%s]) KeyCode: %d, Key: %s, Flags: ctrl=%s, alt=%s, cmd=%s, shift=%s, EventType: %s",
    message or "Key Event",
    appName or "N/A",
    bundleID or "N/A",
    keyCode,
    keyStr,
    tostring(flags.ctrl or false),
    tostring(flags.alt or false),
    tostring(flags.cmd or false),
    tostring(flags.shift or false),
    tostring(e:getType())
  ))
end

------------------------------------------------------------
--  HELPERS  ----------------------------------------------
------------------------------------------------------------
local function isAppBlocked(tbl, bundleID)
  return tbl and bundleID and tbl[bundleID]
end

local function down(flags, mod)
  return flags[mod] and true or false
end

local function flagsEqual(flags, mods)
  return down(flags, "ctrl") == hs_fnutils.contains(mods, "ctrl") and
      down(flags, "alt") == hs_fnutils.contains(mods, "alt") and
      down(flags, "cmd") == hs_fnutils.contains(mods, "cmd") and
      down(flags, "shift") == hs_fnutils.contains(mods, "shift")
end

-- Modified to accept mapped key string
local function launchShortcut(flags, eventKey, isKeyDown, appName, bundleID, originalEvent)
  if not isKeyDown then return false end
  if not eventKey then return false end -- If the key from event is not mapped

  for _, s in ipairs(APP_SHORTCUTS) do
    -- s.key is a string like "delete" or "escape"
    if s.key and flagsEqual(flags, s.mods) and eventKey == s.key then
      logKeyEvent(originalEvent, "remapTap: Launching app shortcut: " .. s.app, appName, bundleID)
      hs_app.launchOrFocus(s.app)
      return true
    end
  end
  return false
end

------------------------------------------------------------
--  GLOBALS FOR KEYTRACKING  -------------------------------
------------------------------------------------------------
local rightAltDown = false

if _G.myActiveTaps.rightAltTap then _G.myActiveTaps.rightAltTap:stop() end
_G.myActiveTaps.rightAltTap = hs_eventtap.new({ hs_eventtap.event.types.flagsChanged }, function(e)
  local kc = e:getKeyCode()
  if kc == 61 then -- right_option
    rightAltDown = e:getFlags().alt
    keyEventsLogger:d("Right Alt (Key 61) state changed. rightAltDown: " .. tostring(rightAltDown))
  end
  return false -- Do not consume the event
end)

if _G.myActiveTaps.altGrTap then _G.myActiveTaps.altGrTap:stop() end
_G.myActiveTaps.altGrTap = hs_eventtap.new({ hs_eventtap.event.types.keyDown }, function(e)
  if not rightAltDown then return false end

  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil"

  local keyCode = e:getKeyCode()
  local key = hs_keycodes.map[keyCode]

  if key then
    logKeyEvent(e, "AltGr key down", appName, bundleID)
    if key == "2" then
      hs_eventtap.keyStroke({ "alt" }, "'", 0) --Produces @ on some layouts with AltGr+2
      return true
    elseif key == "7" then
      hs_eventtap.keyStrokes("{")
      return true
    elseif key == "0" then
      hs_eventtap.keyStrokes("}")
      return true
    end
  end
  return false
end)

------------------------------------------------------------
--  FULLSCREEN BLOCKER ------------------------------------
------------------------------------------------------------
hs_hotkey.bind({ "ctrl", "cmd" }, "F", function()
  local focusedApp = hs_app.frontmostApplication()
  local appName = focusedApp and focusedApp:name() or "N/A"
  local bundleID = focusedApp and focusedApp:bundleID() or "nil"

  if isAppBlocked(FULLSCREEN_BLOCKED_APPS, bundleID) then
    hs_alert.show("Fullscreen disabled 🚫 for " .. appName)
    keyEventsLogger:d("Fullscreen blocked for: " .. appName .. " (" .. bundleID .. ")")
  else
    keyEventsLogger:d("Fullscreen allowed for: " .. appName .. " (" .. bundleID .. "), sending native Ctrl+Cmd+F")
    hs_eventtap.keyStroke({ "ctrl", "cmd" }, "F")
  end
end)

------------------------------------------------------------
--  UNIFIED TAP --------------------------------------------
------------------------------------------------------------
if _G.myActiveTaps.remapTap then _G.myActiveTaps.remapTap:stop() end
_G.myActiveTaps.remapTap = hs_eventtap.new({ hs_eventtap.event.types.keyDown, hs_eventtap.event.types.keyUp },
  function(e)
    local fa = hs_app.frontmostApplication()
    local appName = fa and fa:name() or "N/A"
    local bundleID = fa and fa:bundleID() or "nil"

    logKeyEvent(e, "remapTap Event Received", appName, bundleID)

    local flags = e:getFlags()
    local keyCode = e:getKeyCode()
    local eventIsKeyDown = (e:getType() == hs_eventtap.event.types.keyDown)
    local key = hs_keycodes.map[keyCode] -- Mapped key string, e.g., "a", "return", "left"

    -- 1. Check GLOBAL_SHORTCUTS first
    if key then -- Only proceed if key is mapped for key-based shortcuts
      for _, gs in ipairs(GLOBAL_SHORTCUTS) do
        if gs.key and flagsEqual(flags, gs.mods) and key == gs.key then
          if gs.action then
            gs.action(e, eventIsKeyDown, appName, bundleID) -- Action handles its own logging if needed
            -- Event is consumed because the key combination matched.
            return true
          elseif gs.sendMods and gs.keyOut then
            local desc = gs.description or
            (table.concat(gs.mods, "+") .. "+" .. gs.key .. " -> " .. table.concat(gs.sendMods, "+") .. "+" .. gs.keyOut)
            logKeyEvent(e, "remapTap: GLOBAL Remap: " .. desc, appName, bundleID)
            hs_eventtap.event.newKeyEvent(gs.sendMods, gs.keyOut, eventIsKeyDown):post()
            return true
          end
        end
      end
    end

    -- 2. Check if remapping is blocked for the current application
    if isAppBlocked(REMAP_BLOCKED_APPS, bundleID) then
      keyEventsLogger:d("remapTap: Event in REMAP_BLOCKED_APP, passing through. App: " ..
      appName .. " (" .. bundleID .. ")")
      return false -- Pass through: Do not remap for this app
    end

    -- If key is not mapped (e.g., special media keys not in hs_keycodes.map), pass through
    -- (unless a GLOBAL_SHORTCUT was already matched, possibly one not relying on `key`)
    if not key then
      logKeyEvent(e, "remapTap: Unmapped key (keyCode: " .. keyCode .. "), passing through", appName, bundleID)
      return false
    end

    -- 3. Check for APP_SHORTCUTS (launchers)
    if launchShortcut(flags, key, eventIsKeyDown, appName, bundleID, e) then
      -- launchShortcut already logs
      return true
    end

    -- 4. Check general SHORTCUTS
    for _, r in ipairs(SHORTCUTS) do
      if r.key and flagsEqual(flags, r.mods) and key == r.key then
        local desc = r.description or
        (table.concat(r.mods, "+") .. "+" .. r.key .. " -> " .. table.concat(r.sendMods, "+") .. "+" .. r.keyOut)
        logKeyEvent(e, "remapTap: Remap (SHORTCUTS): " .. desc, appName, bundleID)
        hs_eventtap.event.newKeyEvent(r.sendMods, r.keyOut, eventIsKeyDown):post()
        return true
      end
    end

    logKeyEvent(e, "remapTap: No remap matched, passing through", appName, bundleID)
    return false -- Pass through: No matching remap found
  end)

if _G.myActiveTaps.scrollTap then _G.myActiveTaps.scrollTap:stop() end
_G.myActiveTaps.scrollTap = hs_eventtap.new({ hs_eventtap.event.types.scrollWheel }, function(e)
  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil"

  keyEventsLogger:d("scrollTap Event Received. App: " .. appName .. " (" .. bundleID .. ")")

  if isAppBlocked(REMAP_BLOCKED_APPS, bundleID) then
    keyEventsLogger:d("scrollTap: Scroll in REMAP_BLOCKED_APP, passing through. App: " ..
    appName .. " (" .. bundleID .. ")")
    return false
  end

  local flags = e:getFlags()
  local dy = e:getProperty(hs_eventtap.event.properties.scrollWheelEventDeltaAxis1)

  if flags.ctrl then -- Only check for ctrl key, other modifiers must not be pressed for these specific scroll remaps
    local scrollDirection = dy > 0 and "up" or dy < 0 and "down" or nil
    if scrollDirection then
      for _, shortcut in ipairs(SHORTCUTS) do -- Using SHORTCUTS table for scroll definitions
        if shortcut.scroll and shortcut.scroll == scrollDirection and flagsEqual(flags, shortcut.mods or {}) then
          keyEventsLogger:d("scrollTap: Scroll remap: Ctrl+Scroll" ..
          scrollDirection ..
          " -> " ..
          table.concat(shortcut.sendMods, "+") ..
          "+" .. shortcut.keyOut .. ". App: " .. appName .. " (" .. bundleID .. ")")
          if shortcut.sendMods and shortcut.keyOut then
            hs_eventtap.keyStroke(shortcut.sendMods, shortcut.keyOut, 0) -- keyStroke for zoom is usually fine
          elseif shortcut.action then
            shortcut.action()
          end
          return true -- Consume the scroll event
        end
      end
    end
  end

  keyEventsLogger:d("scrollTap: No scroll remap matched, passing through. App: " .. appName .. " (" .. bundleID .. ")")
  return false
end)

------------------------------------------------------------
--  START TAPS & WATCHER  ----------------------------------
------------------------------------------------------------

_G.myActiveTaps.remapTap:start()
_G.myActiveTaps.scrollTap:start()
_G.myActiveTaps.rightAltTap:start()
_G.myActiveTaps.altGrTap:start()

if _G.myActiveTaps.appWatcher then _G.myActiveTaps.appWatcher:stop() end
_G.myActiveTaps.appWatcher = hs_app.watcher.new(function(appName, eventType, appObject)
  if eventType == hs_app.watcher.activated then
    local bundleID = appObject and appObject:bundleID() or "N/A"
    keyEventsLogger:d("AppWatcher: App activated: " .. appName .. " (" .. bundleID .. ")")
  end
end)
_G.myActiveTaps.appWatcher:start()

hs_alert.show("Windows-like Remapping Active (v2.2 - Refined Logging)")

------------------------------------------------------------
--  DIAGNOSTIC HOTKEY  ------------------------------------
------------------------------------------------------------
hs_hotkey.bind({ "cmd", "alt", "ctrl" }, "T", function()
  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil"
  local currentLayout = hs_keycodes.currentLayout()
  local currentSourceID = hs_keycodes.currentSourceID()

  print("--- DIAGNOSTIC INFO ---")
  print(string.format("Frontmost App: %s (%s)", appName, bundleID))
  print(string.format("Keyboard Layout: %s (Source ID: %s)", currentLayout, currentSourceID))
  print(string.format("DEBUG flag: %s", tostring(DEBUG)))
  print("Tap Statuses:")
  for tapName, tapObj in pairs(_G.myActiveTaps) do
    if type(tapObj) == "table" and tapObj.running then     -- Check if it's a tap object
      print(string.format("  %s: %s", tapName, tapObj:running() and "RUNNING" or "STOPPED"))
    end
  end
  print("-----------------------")
  hs_alert.show(string.format("Diag: %s (%s)", appName, bundleID))
end)
