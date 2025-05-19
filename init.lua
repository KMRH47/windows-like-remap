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
  ["com.apple.Terminal"]        = true,
  ["com.googlecode.iterm2"]     = true,
  ["com.jetbrains.intellij"]    = true,
  ["com.jetbrains.goland"]      = true,
  ["com.jetbrains.pycharm"]     = true,
  ["com.jetbrains.rider"]       = true,
  ["com.jetbrains.WebStorm"]    = true,
  ["com.jetbrains.datagrip"]    = true,
  ["com.jetbrains.clion"]       = true,
  ["com.jetbrains.rustrover"]   = true,
  ["com.microsoft.VSCode"]      = true,
}

-- apps where we want to block Ctrl+Cmd+F (fullscreen)  (BUNDLE-IDs)
local FULLSCREEN_BLOCKED_APPS = {
  ["com.apple.Terminal"]        = true,
  ["com.googlecode.iterm2"]     = true,
  ["com.jetbrains.intellij"]    = true,
  ["com.microsoft.VSCode"]      = true,
  ["com.sublimetext.4"]         = true,
  ["com.apple.dt.Xcode"]        = true,
}

-- declarative shortcut map
local SHORTCUTS = {
  {mods={"ctrl"},               key="c",                    sendMods={"cmd"},                 keyOut="c"},
  {mods={"ctrl"},               key="d",                    sendMods={"cmd"},                 keyOut="d"},
  {mods={"ctrl"},               key="n",                    sendMods={"cmd"},                 keyOut="n"},
  {mods={"ctrl"},               key="v",                    sendMods={"cmd"},                 keyOut="v"},
  {mods={"ctrl"},               key="x",                    sendMods={"cmd"},                 keyOut="x"},
  {mods={"ctrl"},               key="z",                    sendMods={"cmd"},                 keyOut="z"},
  {mods={"ctrl"},               key="a",                    sendMods={"cmd"},                 keyOut="a"},
  {mods={"ctrl"},               key="s",                    sendMods={"cmd"},                 keyOut="s"},
  {mods={"ctrl"},               key="p",                    sendMods={"cmd"},                 keyOut="p"},
  {mods={"ctrl"},               key="f",                    sendMods={"cmd"},                 keyOut="f"},
  {mods={"ctrl"},               key="t",                    sendMods={"cmd"},                 keyOut="t"},
  {mods={"ctrl"},               key="w",                    sendMods={"cmd"},                 keyOut="w"},
  {mods={"ctrl"},               key="return",               sendMods={"cmd"},                 keyOut="return"},
  {mods={"ctrl"},               key="enter",                sendMods={"cmd"},                 keyOut="return"},
  {mods={"ctrl"},               key="y",                    sendMods={"cmd", "shift"},        keyOut="z"},
  {mods={"ctrl"},               key="forwarddelete",        sendMods={"alt"},                 keyOut="forwarddelete"},
  {mods={"ctrl"},               key="delete",               sendMods={"alt"},                 keyOut="delete"},
  {mods={"ctrl"},               key="r",                    sendMods={"cmd"},                 keyOut="r"},

  {mods={"ctrl", "shift"},      key="r",                    sendMods={"cmd", "shift"},        keyOut="r"},
  {mods={"ctrl", "shift"},      key="e",                    sendMods={"cmd", "alt"},          keyOut="e"},
  {mods={"ctrl", "shift"},      key="c",                    sendMods={"cmd", "alt"},          keyOut="c"},
  {mods={"ctrl", "shift"},      key="k",                    sendMods={"cmd", "alt"},          keyOut="k"},

  {mods={"ctrl"},               scroll="up",                sendMods={"cmd"},                 keyOut="+"},
  {mods={"ctrl"},               scroll="down",              sendMods={"cmd"},                 keyOut="-"},

  {mods={"ctrl", "alt"},        key="¨",                    sendMods={"alt"},                 keyOut="¨"},
  {mods={"ctrl", "alt"},        key="down",                 sendMods={"cmd"},                 keyOut="-"},

  {mods={"ctrl", "shift"},      key="b",                    sendMods={"cmd", "shift"},        keyOut="b"},
}     
      
local APP_SHORTCUTS = {     
  {mods={"ctrl", "alt"},        key="delete", app="Activity Monitor"},
  {mods={"ctrl", "shift"},      key="escape", app="Activity Monitor"},
}

------------------------------------------------------------
--  DEBUG LOGGER  -----------------------------------------
------------------------------------------------------------
local DEBUG = false -- IMPORTANT: Keep true for now
local keyEventsLogger = hs_logger.new('keyEvents', 'debug')

local function logKeyEvent(e, message, appName, bundleID)
  if not DEBUG then return end
  
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

local function launchShortcut(flags, keyCode, isKeyDown)
  if not isKeyDown then return false end
  for _, s in ipairs(APP_SHORTCUTS) do
    if s.key and hs_keycodes.map[s.key] and flagsEqual(flags, s.mods) and keyCode == hs_keycodes.map[s.key] then
      hs_app.launchOrFocus(s.app)
      return true
    end
  end
  return false
end

------------------------------------------------------------
--  GLOBALS FOR KEYTRACKING  -------------------------------
------------------------------------------------------------
local rightAltDown = false -- This is a global variable, be mindful

if _G.myActiveTaps.rightAltTap then _G.myActiveTaps.rightAltTap:stop() end
_G.myActiveTaps.rightAltTap = hs_eventtap.new({hs_eventtap.event.types.flagsChanged}, function(e)
  local kc = e:getKeyCode()
  if kc == 61 then -- right_option
    rightAltDown = e:getFlags().alt
    if DEBUG then keyEventsLogger:d("Right Alt (Key 61) state changed. rightAltDown: " .. tostring(rightAltDown)) end
  end
  return false
end)

if _G.myActiveTaps.altGrTap then _G.myActiveTaps.altGrTap:stop() end
_G.myActiveTaps.altGrTap = hs_eventtap.new({hs_eventtap.event.types.keyDown}, function(e)
  if not rightAltDown then return false end

  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil"

  local keyCode = e:getKeyCode()
  local key = hs_keycodes.map[keyCode]
  
  if key then
    if DEBUG then logKeyEvent(e, "AltGr key down", appName, bundleID) end
    if key == "2" then
      hs_eventtap.keyStroke({"alt"}, "'", 0)
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
hs_hotkey.bind({"ctrl", "cmd"}, "F", function()
  local focusedApp = hs_app.frontmostApplication()
  local appName = focusedApp and focusedApp:name() or "N/A"
  local bundleID = focusedApp and focusedApp:bundleID() or "nil"
  
  if isAppBlocked(FULLSCREEN_BLOCKED_APPS, bundleID) then
    hs_alert.show("Fullscreen disabled 🚫 for " .. appName)
    if DEBUG then keyEventsLogger:d("Fullscreen blocked for: " .. appName .. " (" .. bundleID .. ")") end
  else
    if DEBUG then keyEventsLogger:d("Fullscreen allowed for: " .. appName .. " (" .. bundleID .. "), sending native Ctrl+Cmd+F") end
    hs_eventtap.keyStroke({"ctrl", "cmd"}, "F")
  end
end)

------------------------------------------------------------
--  UNIFIED TAP --------------------------------------------
------------------------------------------------------------
if _G.myActiveTaps.remapTap then _G.myActiveTaps.remapTap:stop() end
_G.myActiveTaps.remapTap = hs_eventtap.new({hs_eventtap.event.types.keyDown, hs_eventtap.event.types.keyUp}, function(e)
  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil" -- Use "nil" string if actual nil

  if DEBUG then logKeyEvent(e, "remapTap Event Received", appName, bundleID) end

  if isAppBlocked(REMAP_BLOCKED_APPS, bundleID) then
    if DEBUG then keyEventsLogger:d("remapTap: Event in REMAP_BLOCKED_APP, passing through. App: " .. appName .. " (" .. bundleID .. ")") end
    return false
  end

  local flags = e:getFlags()
  local keyCode = e:getKeyCode()
  local eventIsKeyDown = (e:getType() == hs_eventtap.event.types.keyDown)
  
  local key = hs_keycodes.map[keyCode]
  if not key then
    if DEBUG then logKeyEvent(e, "remapTap: Unmapped key, passing through", appName, bundleID) end
    return false
  end

  if flags.cmd and not (flags.ctrl or flags.alt or flags.shift) and key == "." and eventIsKeyDown then
    if DEBUG then logKeyEvent(e, "remapTap: Emoji Picker (Cmd+.) -> Ctrl+Cmd+Space", appName, bundleID) end
    hs_eventtap.keyStroke({"ctrl", "cmd"}, "space", 0)
    return true
  end

  if flags.cmd and flags.shift and not (flags.ctrl or flags.alt) and key == "down" and eventIsKeyDown then
    if DEBUG then logKeyEvent(e, "remapTap: Minimize Window (Cmd+Shift+Down) -> Cmd+M", appName, bundleID) end
    hs_eventtap.keyStroke({"cmd"}, "m", 0)
    return true
  end

  if launchShortcut(flags, keyCode, eventIsKeyDown) then
    if DEBUG then logKeyEvent(e, "remapTap: App shortcut launched", appName, bundleID) end
    return true
  end

  if flags.ctrl and not (flags.alt or flags.cmd or flags.shift) and (key == "left" or key == "right") then
    if DEBUG then logKeyEvent(e, "remapTap: Ctrl+Arrow -> Alt+Arrow", appName, bundleID) end
    hs_eventtap.event.newKeyEvent({"alt"}, key, eventIsKeyDown):post()
    return true
  end

  for _, r in ipairs(SHORTCUTS) do
    if r.key and flagsEqual(flags, r.mods) and key == r.key then
      if DEBUG then logKeyEvent(e, "remapTap: Declarative remap: " .. table.concat(r.mods, "+") .. "+" .. r.key .. " -> " .. table.concat(r.sendMods, "+") .. "+" .. r.keyOut, appName, bundleID) end
      hs_eventtap.event.newKeyEvent(r.sendMods, r.keyOut, eventIsKeyDown):post()
      return true
    end
  end

  if DEBUG then logKeyEvent(e, "remapTap: No remap matched, passing through", appName, bundleID) end
  return false
end)

if _G.myActiveTaps.scrollTap then _G.myActiveTaps.scrollTap:stop() end
_G.myActiveTaps.scrollTap = hs_eventtap.new({hs_eventtap.event.types.scrollWheel}, function(e)
  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil"

  if DEBUG then keyEventsLogger:d("scrollTap Event Received. App: " .. appName .. " (" .. bundleID .. ")") end

  if isAppBlocked(REMAP_BLOCKED_APPS, bundleID) then
    if DEBUG then keyEventsLogger:d("scrollTap: Scroll in REMAP_BLOCKED_APP, passing through. App: " .. appName .. " (" .. bundleID .. ")") end
    return false
  end

  local flags = e:getFlags()
  local dy = e:getProperty(hs_eventtap.event.properties.scrollWheelEventDeltaAxis1)

  if flags.ctrl then
    local scrollDirection = dy > 0 and "up" or dy < 0 and "down" or nil
    if scrollDirection then
      for _, shortcut in ipairs(SHORTCUTS) do
        if shortcut.scroll == scrollDirection and flagsEqual(flags, shortcut.mods or {}) then
          if DEBUG then keyEventsLogger:d("scrollTap: Scroll remap: Ctrl+Scroll" .. scrollDirection .. " -> " .. table.concat(shortcut.sendMods, "+") .. "+" .. shortcut.keyOut .. ". App: " .. appName .. " (" .. bundleID .. ")") end
          if shortcut.sendMods and shortcut.keyOut then
            hs_eventtap.keyStroke(shortcut.sendMods, shortcut.keyOut, 0)
          elseif shortcut.action then
            shortcut.action()
          end
          return true
        end
      end
    end
  end
  
  if DEBUG then keyEventsLogger:d("scrollTap: No scroll remap matched, passing through. App: " .. appName .. " (" .. bundleID .. ")") end
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
    if DEBUG then keyEventsLogger:d("AppWatcher: App activated: " .. appName .. " (" .. bundleID .. ")") end
  end
end)
_G.myActiveTaps.appWatcher:start()

hs_alert.show("Windows-like Remapping Active (v2)")

------------------------------------------------------------
--  DIAGNOSTIC HOTKEY  ------------------------------------
------------------------------------------------------------
hs_hotkey.bind({"cmd", "alt", "ctrl"}, "T", function()
    local fa = hs_app.frontmostApplication()
    local appName = fa and fa:name() or "N/A"
    local bundleID = fa and fa:bundleID() or "nil"
    local currentLayout = hs_keycodes.currentLayout()
    local currentSourceID = hs_keycodes.currentSourceID()

    print("--- DIAGNOSTIC INFO ---")
    print(string.format("Frontmost App: %s (%s)", appName, bundleID))
    print(string.format("Keyboard Layout: %s (Source ID: %s)", currentLayout, currentSourceID))

    print("Tap Statuses:")
    for tapName, tapObj in pairs(_G.myActiveTaps) do
        if type(tapObj) == "table" and tapObj.running then -- Check if it's a tap object
            print(string.format("  %s: %s", tapName, tapObj:running() and "RUNNING" or "STOPPED"))
        end
    end
    print("-----------------------")
    hs_alert.show(string.format("Diag: %s (%s)", appName, bundleID))
end)
