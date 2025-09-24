--  CONFIG  ------------------------------------------------
------------------------------------------------------------
local hs_app = require "hs.application"
local hs_eventtap = require "hs.eventtap"
local hs_keycodes = require "hs.keycodes"
local hs_hotkey = require "hs.hotkey"
local hs_alert = require "hs.alert"
local hs_fnutils = require "hs.fnutils"
local hs_logger = require "hs.logger"
local hs_mouse = require "hs.mouse"

-- Ensure our global table for taps exists
_G.myActiveTaps = _G.myActiveTaps or {}

-- apps where we *never* want Ctrl→Cmd remaps  (BUNDLE-IDs)
local REMAP_BLOCKED_APPS = {
  ["net.kovidgoyal.kitty"]          = true,
  ["com.apple.Terminal"]            = true,
  ["com.googlecode.iterm2"]         = true,
  ["com.jetbrains.intellij"]        = true,
  ["com.jetbrains.goland"]          = true,
  ["com.jetbrains.pycharm"]         = true,
  ["com.jetbrains.rider"]           = true,
  ["com.jetbrains.WebStorm"]        = true,
  ["com.jetbrains.datagrip"]        = true,
  ["com.jetbrains.clion"]           = true,
  ["com.jetbrains.rustrover"]       = true,
  ["com.microsoft.VSCode"]          = true,
  ["com.todesktop.230313mzl4w4u92"] = true,
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

-- ===== FAST Kitty-only Ctrl+C / Ctrl+V remap (no lag) =====
-- Replace your kittyTap block with this:

local kittyBundle = "net.kovidgoyal.kitty"

if _G.kittyFastTap then _G.kittyFastTap:stop() end
_G.kittyFastTap = hs.eventtap.new(
  { hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
  function(e)
    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= kittyBundle then
      return false -- not Kitty -> pass through
    end

    local isDown = (e:getType() == hs.eventtap.event.types.keyDown)
    local flags  = e:getFlags()
    local key    = hs.keycodes.map[e:getKeyCode()]

    -- Only Ctrl (no cmd/alt/shift)
    local onlyCtrl = flags.ctrl and not (flags.cmd or flags.alt or flags.shift)

    -- Ctrl+C -> Cmd+C (copy)
    if onlyCtrl and key == "c" then
      hs.eventtap.event.newKeyEvent({ "cmd" }, "c", isDown):post()
      return true
    end

    -- Ctrl+V -> Cmd+V (paste)
    if onlyCtrl and key == "v" then
      hs.eventtap.event.newKeyEvent({ "cmd" }, "v", isDown):post()
      return true
    end

    return false
  end
)
_G.kittyFastTap:start()


------------------------------------------------------------
--  GLOBAL_SHORTCUTS
------------------------------------------------------------
_G.minimizedStack = _G.minimizedStack or {} -- keep only one copy

local GLOBAL_SHORTCUTS = {
  -- Cmd‑Shift‑Down  → minimise front window, reveal first other‑app window
  {
    mods        = { "cmd", "shift" },
    key         = "down",
    action      = function(_, isDown)
      if not isDown then return end

      local front = hs.window.frontmostWindow()
      if not front then return end
      local frontApp = front:application():bundleID()

      -- find the first non‑minimised window from *another* app
      local fallback = nil
      for _, w in ipairs(hs.window.orderedWindows()) do
        if w:id() ~= front:id()
            and not w:isMinimized()
            and (w:application():bundleID() ~= frontApp) then
          fallback = w
          break
        end
      end

      -- push to stack and minimise
      _G.minimizedStack = _G.minimizedStack or {}
      table.insert(_G.minimizedStack, front:id())
      front:minimize()

      -- after the system finishes its own focus shuffle (~0.25 s), bring fallback forward
      if fallback then
        hs.timer.doAfter(0.3, function()
          if fallback and not fallback:isMinimized() then
            fallback:focus()
          end
        end)
      end
    end,
    description = "Minimise window and reveal first other‑app window behind",
  },

  -------- restore (Cmd-Shift-Up) --------------------------
  {
    mods        = { "cmd", "shift" },
    key         = "up",
    action      = function(_, isDown)
      if not isDown then return end

      while #_G.minimizedStack > 0 do
        local id  = table.remove(_G.minimizedStack) -- pop
        local win = hs.window.get(id)
        if win and win:isMinimized() then
          win:unminimize()
          win:focus()
          return
        end
        -- if win no longer exists or was restored some other way, keep popping
      end

      hs.alert.show("No minimised windows")
    end,
    description = "Restore most-recent minimised window",
  },

} -- <<<--- keep this closing brace, nothing after it


-- declarative shortcut map (general remaps)
local SHORTCUTS = {
  { mods = { "ctrl" },          key = "c",             sendMods = { "cmd" },          keyOut = "c" },
  { mods = { "ctrl" },          key = "d",             sendMods = { "cmd" },          keyOut = "d" },
  { mods = { "ctrl" },          key = "n",             sendMods = { "cmd" },          keyOut = "n" },
  { mods = { "ctrl" },          key = "v",             sendMods = { "cmd" },          keyOut = "v" },
  { mods = { "ctrl" },          key = "x",             sendMods = { "cmd" },          keyOut = "x" },
  { mods = { "ctrl" },          key = "z",             sendMods = { "cmd" },          keyOut = "z" },
  { mods = { "ctrl" },          key = "a",             sendMods = { "cmd" },          keyOut = "a" },
  { mods = { "ctrl" },          key = "s",             sendMods = { "cmd" },          keyOut = "s" },
  { mods = { "ctrl" },          key = "p",             sendMods = { "cmd" },          keyOut = "p" },
  { mods = { "ctrl" },          key = "f",             sendMods = { "cmd" },          keyOut = "f" },
  { mods = { "ctrl" },          key = "t",             sendMods = { "cmd" },          keyOut = "t" },
  { mods = { "ctrl" },          key = "w",             sendMods = { "cmd" },          keyOut = "w" },
  { mods = { "ctrl" },          key = "return",        sendMods = { "cmd" },          keyOut = "return" },
  { mods = { "ctrl" },          key = "enter",         sendMods = { "cmd" },          keyOut = "return" }, -- 'enter' is often the same as 'return'
  { mods = { "ctrl" },          key = "y",             sendMods = { "cmd", "shift" }, keyOut = "z" },      -- Redo
  { mods = { "ctrl" },          key = "forwarddelete", sendMods = { "alt" },          keyOut = "forwarddelete" },
  { mods = { "ctrl" },          key = "delete",        sendMods = { "alt" },          keyOut = "delete" },
  { mods = { "ctrl" },          key = "r",             sendMods = { "cmd" },          keyOut = "r" },

  { mods = { "ctrl" },          key = "left",          sendMods = { "alt" },          keyOut = "left" },
  { mods = { "ctrl" },          key = "right",         sendMods = { "alt" },          keyOut = "right" },

  { mods = { "ctrl", "shift" }, key = "r",             sendMods = { "cmd", "shift" }, keyOut = "r" },
  { mods = { "ctrl", "shift" }, key = "e",             sendMods = { "cmd", "alt" },   keyOut = "e" },
  { mods = { "ctrl", "shift" }, key = "c",             sendMods = { "cmd", "alt" },   keyOut = "c" },
  { mods = { "ctrl", "shift" }, key = "k",             sendMods = { "cmd", "alt" },   keyOut = "k" },

  { mods = { "ctrl" },          scroll = "up",         sendMods = { "cmd" },          keyOut = "+" }, -- Zoom in
  { mods = { "ctrl" },          scroll = "down",       sendMods = { "cmd" },          keyOut = "-" }, -- Zoom out

  { mods = { "ctrl", "alt" },   key = "¨",             sendMods = { "alt" },          keyOut = "¨" }, -- Example, adjust key as needed for your layout
  { mods = { "ctrl", "alt" },   key = "down",          sendMods = { "cmd" },          keyOut = "-" }, -- Example, might conflict with scroll

  { mods = { "ctrl", "shift" }, key = "b",             sendMods = { "cmd", "shift" }, keyOut = "b" },

}

-- app specific launchers
local APP_SHORTCUTS = {
  { mods = { "ctrl", "alt" },   key = "delete", app = "Activity Monitor" },
  { mods = { "ctrl", "shift" }, key = "escape", app = "Activity Monitor" },
}

------------------------------------------------------------
--  DEBUG LOGGER  -----------------------------------------
------------------------------------------------------------
local DEBUG = true -- IMPORTANT: Keep true for now (as per your comment)
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

-- Modified to accept mapped key string
local function launchShortcut(flags, eventKey, isKeyDown, appName, bundleID, originalEvent)
  if not isKeyDown then return false end
  if not eventKey then return false end -- If the key from event is not mapped

  for _, s in ipairs(APP_SHORTCUTS) do
    -- s.key is a string like "delete" or "escape"
    if s.key and flagsEqual(flags, s.mods) and eventKey == s.key then
      if DEBUG then logKeyEvent(originalEvent, "remapTap: Launching app shortcut: " .. s.app, appName, bundleID) end
      hs_app.launchOrFocus(s.app)
      return true
    end
  end
  return false
end

------------------------------------------------------------
--  GLOBALS FOR KEYTRACKING  -------------------------------
------------------------------------------------------------
_G.rightAltDown = false

if _G.myActiveTaps.rightAltTap then _G.myActiveTaps.rightAltTap:stop() end
_G.myActiveTaps.rightAltTap = hs_eventtap.new({ hs_eventtap.event.types.flagsChanged }, function(e)
  local kc = e:getKeyCode()
  if kc == 61 then -- right_option
    _G.rightAltDown = e:getFlags().alt
    if DEBUG then keyEventsLogger:d("Right Alt (Key 61) state changed. rightAltDown: " .. tostring(_G.rightAltDown)) end
  end
  return false -- Do not consume the event
end)

if _G.myActiveTaps.altGrTap then _G.myActiveTaps.altGrTap:stop() end
_G.myActiveTaps.altGrTap = hs_eventtap.new({ hs_eventtap.event.types.keyDown }, function(e)
  if not _G.rightAltDown then return false end

  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil"

  local keyCode = e:getKeyCode()
  local key = hs_keycodes.map[keyCode]

  if key then
    if DEBUG then logKeyEvent(e, "AltGr key down", appName, bundleID) end
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
--  MOUSE HANDLING  ---------------------------------------
------------------------------------------------------------
if _G.myActiveTaps.mouseTap then _G.myActiveTaps.mouseTap:stop() end
_G.myActiveTaps.mouseTap = hs_eventtap.new({
  hs_eventtap.event.types.leftMouseDown,
  hs_eventtap.event.types.leftMouseUp,
  hs_eventtap.event.types.leftMouseDragged
}, function(e)
  local flags = e:getFlags()

  if flags.ctrl then
    if DEBUG then
      local fa = hs_app.frontmostApplication()
      local appName = fa and fa:name() or "N/A"
      local bundleID = fa and fa:bundleID() or "nil"
      local eventType = e:getType()
      local eventTypeStr = eventType == hs_eventtap.event.types.leftMouseDown and "leftMouseDown" or
          eventType == hs_eventtap.event.types.leftMouseUp and "leftMouseUp" or
          eventType == hs_eventtap.event.types.leftMouseDragged and "leftMouseDragged" or
          "unknown"
      keyEventsLogger:d(string.format("mouseTap: Ctrl+Click intercepted (%s). App: %s (%s)",
        eventTypeStr, appName, bundleID))
    end

    local copy = e:copy()
    copy:setFlags({}) -- Remove all modifier flags
    copy:post()
    return true       -- Consume the original event
  end

  return false -- Pass through all other mouse events
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
    if DEBUG then keyEventsLogger:d("Fullscreen blocked for: " .. appName .. " (" .. bundleID .. ")") end
  else
    if DEBUG then
      keyEventsLogger:d("Fullscreen allowed for: " ..
        appName .. " (" .. bundleID .. "), sending native Ctrl+Cmd+F")
    end
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

    if DEBUG then logKeyEvent(e, "remapTap Event Received", appName, bundleID) end

    local flags = e:getFlags()
    local keyCode = e:getKeyCode()
    local eventIsKeyDown = (e:getType() == hs_eventtap.event.types.keyDown)
    local key = hs_keycodes.map[keyCode] -- Mapped key string, e.g., "a", "return", "left"

    -- AltGr + Return → context click at mouse, preserve selection
    _G.altGrReturnArmed = _G.altGrReturnArmed or false


    -- 1. Check GLOBAL_SHORTCUTS first
    if key then -- Only proceed if key is mapped for key-based shortcuts
      for _, gs in ipairs(GLOBAL_SHORTCUTS) do
        if gs.key and flagsEqual(flags, gs.mods) and key == gs.key then
          if gs.action then
            gs.action(e, eventIsKeyDown, appName, bundleID) -- Action handles its own logging if needed
            -- Event is consumed because the key combination matched.
            return true
          elseif gs.sendMods and gs.keyOut then
            if DEBUG then
              local desc = gs.description or
                  (table.concat(gs.mods, "+") .. "+" .. gs.key .. " -> " .. table.concat(gs.sendMods, "+") .. "+" .. gs.keyOut)
              logKeyEvent(e, "remapTap: GLOBAL Remap: " .. desc, appName, bundleID)
            end
            hs_eventtap.event.newKeyEvent(gs.sendMods, gs.keyOut, eventIsKeyDown):post()
            return true
          end
        end
      end
    end

    -- 2. Check if remapping is blocked for the current application
    if isAppBlocked(REMAP_BLOCKED_APPS, bundleID) then
      if DEBUG then
        keyEventsLogger:d("remapTap: Event in REMAP_BLOCKED_APP, passing through. App: " ..
          appName .. " (" .. bundleID .. ")")
      end
      return false -- Pass through: Do not remap for this app
    end

    -- If key is not mapped (e.g., special media keys not in hs_keycodes.map), pass through
    -- (unless a GLOBAL_SHORTCUT was already matched, possibly one not relying on `key`)
    if not key then
      if DEBUG then
        logKeyEvent(e, "remapTap: Unmapped key (keyCode: " .. keyCode .. "), passing through", appName,
          bundleID)
      end
      return false
    end

    -- 3. Check for APP_SHORTCUTS (launchers)
    if launchShortcut(flags, key, eventIsKeyDown, appName, bundleID, e) then
      -- launchShortcut already logs if DEBUG is true
      return true
    end

    -- 4. Check general SHORTCUTS
    for _, r in ipairs(SHORTCUTS) do
      if r.key and flagsEqual(flags, r.mods) and key == r.key then
        if DEBUG then
          local desc = r.description or
              (table.concat(r.mods, "+") .. "+" .. r.key .. " -> " .. table.concat(r.sendMods, "+") .. "+" .. r.keyOut)
          logKeyEvent(e, "remapTap: Remap (SHORTCUTS): " .. desc, appName, bundleID)
        end
        hs_eventtap.event.newKeyEvent(r.sendMods, r.keyOut, eventIsKeyDown):post()
        return true
      end
    end

    if DEBUG then logKeyEvent(e, "remapTap: No remap matched, passing through", appName, bundleID) end
    return false -- Pass through: No matching remap found
  end)

if _G.myActiveTaps.scrollTap then _G.myActiveTaps.scrollTap:stop() end
_G.myActiveTaps.scrollTap = hs_eventtap.new({ hs_eventtap.event.types.scrollWheel }, function(e)
  local fa = hs_app.frontmostApplication()
  local appName = fa and fa:name() or "N/A"
  local bundleID = fa and fa:bundleID() or "nil"

  if DEBUG then keyEventsLogger:d("scrollTap Event Received. App: " .. appName .. " (" .. bundleID .. ")") end

  if isAppBlocked(REMAP_BLOCKED_APPS, bundleID) then
    if DEBUG then
      keyEventsLogger:d("scrollTap: Scroll in REMAP_BLOCKED_APP, passing through. App: " ..
        appName .. " (" .. bundleID .. ")")
    end
    return false
  end

  local flags = e:getFlags()
  local dy = e:getProperty(hs_eventtap.event.properties.scrollWheelEventDeltaAxis1)

  if flags.ctrl then -- Only check for ctrl key, other modifiers must not be pressed for these specific scroll remaps
    local scrollDirection = dy > 0 and "up" or dy < 0 and "down" or nil
    if scrollDirection then
      for _, shortcut in ipairs(SHORTCUTS) do -- Using SHORTCUTS table for scroll definitions
        if shortcut.scroll and shortcut.scroll == scrollDirection and flagsEqual(flags, shortcut.mods or {}) then
          if DEBUG then
            keyEventsLogger:d("scrollTap: Scroll remap: Ctrl+Scroll" ..
              scrollDirection ..
              " -> " ..
              table.concat(shortcut.sendMods, "+") ..
              "+" .. shortcut.keyOut .. ". App: " .. appName .. " (" .. bundleID .. ")")
          end
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

  if DEBUG then
    keyEventsLogger:d("scrollTap: No scroll remap matched, passing through. App: " ..
      appName .. " (" .. bundleID .. ")")
  end
  return false
end)

------------------------------------------------------------
--  START TAPS & WATCHER  ----------------------------------
------------------------------------------------------------

_G.myActiveTaps.remapTap:start()
_G.myActiveTaps.scrollTap:start()
_G.myActiveTaps.rightAltTap:start()
_G.myActiveTaps.altGrTap:start()
_G.myActiveTaps.mouseTap:start()

if _G.myActiveTaps.appWatcher then _G.myActiveTaps.appWatcher:stop() end
_G.myActiveTaps.appWatcher = hs_app.watcher.new(function(appName, eventType, appObject)
  if eventType == hs_app.watcher.activated then
    local bundleID = appObject and appObject:bundleID() or "N/A"
    if DEBUG then keyEventsLogger:d("AppWatcher: App activated: " .. appName .. " (" .. bundleID .. ")") end
  end
end)
_G.myActiveTaps.appWatcher:start()

hs_alert.show("Windows-like Remapping Active (v2.2 - Global Shortcuts & Mouse Support)")

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
    if type(tapObj) == "table" and tapObj.running then -- Check if it's a tap object
      print(string.format("  %s: %s", tapName, tapObj:running() and "RUNNING" or "STOPPED"))
    end
  end
  print("-----------------------")
  hs_alert.show(string.format("Diag: %s (%s)", appName, bundleID))
end)


-- Special handling for keypad Enter (keyCode 76) + Ctrl → Cmd+Return
if _G.myActiveTaps.keypadEnterRemap then _G.myActiveTaps.keypadEnterRemap:stop() end
_G.myActiveTaps.keypadEnterRemap = hs_eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp },
  function(e)
    local isDown = e:getType() == hs.eventtap.event.types.keyDown
    if e:getKeyCode() == 76 and e:getFlags():containExactly({ "ctrl" }) then
      hs_eventtap.event.newKeyEvent({ "cmd" }, "return", isDown):post()
      return true
    end
    return false
  end)
_G.myActiveTaps.keypadEnterRemap:start()
