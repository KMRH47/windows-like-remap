------------------------------------------------------------
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
local hasAX, hs_ax = pcall(require, "hs.axuielement")

------------------------------------------------------------
--  AX ENHANCED UI KILLER (stops slow resize animations)
------------------------------------------------------------
function withNoEnhancedUI(w, fn)
  if not fn then return end
  if not hasAX or not w or not w.application then
    fn()
    return
  end

  local ok, axApp = pcall(hs_ax.applicationElement, w:application())
  if not ok or not axApp then
    fn()
    return
  end

  local wasEnhanced = axApp.AXEnhancedUserInterface
  if wasEnhanced then axApp.AXEnhancedUserInterface = false end

  fn()

  if wasEnhanced then axApp.AXEnhancedUserInterface = true end
end

------------------------------------------------------------
--  GLOBAL macOS ANIMATION KILL-SWITCH (Raycast-style)
------------------------------------------------------------
-- This applies the same kind of defaults many tilers / power users use
-- to strip as many system animations as macOS currently allows.
local function disableGlobalAnimations()
  local cmds = {
    -- General window / sheet / resize animations
    'defaults write -g NSAutomaticWindowAnimationsEnabled -bool false',
    'defaults write -g NSWindowResizeTime -float 0.001',
    'defaults write -g QLPanelAnimationDuration -float 0',
    'defaults write -g NSScrollAnimationEnabled -bool false',
    'defaults write -g NSScrollViewRubberbanding -bool false',
    'defaults write -g NSDocumentRevisionsWindowTransformAnimation -bool false',
    'defaults write -g NSToolbarFullScreenAnimationDuration -float 0',
    'defaults write -g NSBrowserColumnAnimationSpeedMultiplier -float 0',

    -- “Reduce motion” everywhere
    'defaults write NSGlobalDomain ReduceMotionEnabled -bool true',

    -- Dock / Mission Control / Launchpad timing
    'defaults write com.apple.dock autohide-time-modifier -float 0',
    'defaults write com.apple.dock autohide-delay -float 0',
    'defaults write com.apple.dock expose-animation-duration -float 0',
    'defaults write com.apple.dock springboard-show-duration -float 0',
    'defaults write com.apple.dock springboard-hide-duration -float 0',
    'defaults write com.apple.dock springboard-page-duration -float 0',
  }

  for _, c in ipairs(cmds) do
    os.execute(c .. ' >/dev/null 2>&1')
  end

  -- Needed for a bunch of Dock-related keys to apply
  os.execute('killall Dock >/dev/null 2>&1')
end

disableGlobalAnimations()


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

    local isDown   = (e:getType() == hs.eventtap.event.types.keyDown)
    local flags    = e:getFlags()
    local key      = hs.keycodes.map[e:getKeyCode()]

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

  ----------------------------------------------------------------------
  -- Cmd-Shift-Down → HIDE window + reveal next app window
  ----------------------------------------------------------------------
  {
    mods        = { "cmd", "shift" },
    key         = "down",
    action      = function(_, isDown)
      if not isDown then return end

      local front = hs.window.frontmostWindow()
      if not front then return end

      -- store window + original space
      _G.hiddenWindows = _G.hiddenWindows or {}
      local currentSpace = hs.spaces.focusedSpace()
      table.insert(_G.hiddenWindows, { window = front, space = currentSpace })

      -- find a different space to banish the window to
      local allSpaces = hs.spaces.allSpaces()
      local targetSpace = nil
      for _, spaces in pairs(allSpaces) do
        for _, spaceID in ipairs(spaces) do
          if spaceID ~= currentSpace then
            targetSpace = spaceID
            break
          end
        end
        if targetSpace then break end
      end

      if targetSpace then
        -- move window to different space (instant, invisible)
        hs.spaces.moveWindowToSpace(front, targetSpace)
      else
        -- fallback: still only this window, but avoid Enhanced UI animations if possible
        withNoEnhancedUI(front, function()
          front:minimize()
        end)
      end

      -- focus next window
      hs.timer.doAfter(0.01, function()
        local windows = hs.window.orderedWindows()
        for _, w in ipairs(windows) do
          if w ~= front then
            w:focus()
            break
          end
        end
      end)
    end,
    description = "Instant hide current window",
  },

  ----------------------------------------------------------------------
  -- Cmd-Shift-Up → RESTORE last hidden window instantly
  ----------------------------------------------------------------------
  {
    mods        = { "cmd", "shift" },
    key         = "up",
    action      = function(_, isDown)
      if not isDown then return end

      _G.hiddenWindows = _G.hiddenWindows or {}

      while #_G.hiddenWindows > 0 do
        local entry = table.remove(_G.hiddenWindows)
        local w = entry and entry.window
        local space = entry and entry.space
        if w then
          -- move window back to original space and focus
          if space then
            hs.spaces.moveWindowToSpace(w, space)
          end
          w:focus()
          return
        end
      end

      hs.alert.show("No hidden windows")
    end,
    description = "Instant restore last hidden window",
  },
  ----------------------------------------------------------------------
  -- Cmd-. → Emoji picker (sends Ctrl+Cmd+Space)
  ----------------------------------------------------------------------

  {
    mods        = { "cmd" },
    key         = ".",
    action      = function(_, isDown)
      if not isDown then return end
      hs.eventtap.keyStroke({ "ctrl", "cmd" }, "space", 0)
    end,
    description = "Emoji picker",
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
  { mods = { "ctrl", "shift" }, key = "t",             sendMods = { "cmd", "shift" }, keyOut = "t" },
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
local DEBUG = true -- Set to true only when troubleshooting
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
  if e:getKeyCode() == 61 then -- right_option
    _G.rightAltDown = e:getFlags().alt
  end
  return false
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
--  MOUSE HANDLING  — left Ctrl click becomes Cmd click
------------------------------------------------------------
_G.leftCtrlDown          = _G.leftCtrlDown or false
_G.rightCtrlDown         = _G.rightCtrlDown or false

-- Track left vs right Ctrl keys explicitly, plus fn/globe key
if _G.myActiveTaps.ctrlSideTap then _G.myActiveTaps.ctrlSideTap:stop() end
_G.myActiveTaps.ctrlSideTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(e)
  local kc = e:getKeyCode()
  if kc == 59 then     -- left control
    _G.leftCtrlDown = e:getFlags().ctrl
  elseif kc == 62 then -- right control (also fn/globe key when mapped to Control)
    _G.rightCtrlDown = e:getFlags().ctrl
  elseif kc == 63 then -- fn key (globe key on some Macs when mapped to Control)
    _G.leftCtrlDown = e:getFlags().ctrl
  end
  return false
end)
_G.myActiveTaps.ctrlSideTap:start()

-- Convert Ctrl + left click to Cmd + left click (works with both left and right Ctrl)
if _G.myActiveTaps.mouseTap then _G.myActiveTaps.mouseTap:stop() end
_G.myActiveTaps.mouseTap = hs.eventtap.new({
  hs.eventtap.event.types.leftMouseDown,
  hs.eventtap.event.types.leftMouseUp,
  hs.eventtap.event.types.leftMouseDragged
}, function(e)
  -- Rewrite when the user is holding either left OR right Ctrl
  if (_G.leftCtrlDown or _G.rightCtrlDown) and e:getFlags().ctrl then
    local copy = e:copy()
    copy:setFlags({ cmd = true })
    copy:post()
    return true
  end
  return false
end)
_G.myActiveTaps.mouseTap:start()



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

  -- Only remap if LEFT Ctrl is down (not right Ctrl)
  -- This allows right Ctrl (fn/globe) + scroll to work natively in web apps like Figma
  if flags.ctrl and _G.leftCtrlDown and not _G.rightCtrlDown then
    local scrollDirection = dy > 0 and "up" or dy < 0 and "down" or nil
    if scrollDirection then
      for _, shortcut in ipairs(SHORTCUTS) do
        if shortcut.scroll and shortcut.scroll == scrollDirection and flagsEqual(flags, shortcut.mods or {}) then
          if DEBUG then
            keyEventsLogger:d("scrollTap: Scroll remap: Ctrl+Scroll" ..
              scrollDirection ..
              " -> " ..
              table.concat(shortcut.sendMods, "+") ..
              "+" .. shortcut.keyOut .. ". App: " .. appName .. " (" .. bundleID .. ")")
          end
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

  if DEBUG then
    keyEventsLogger:d("scrollTap: No scroll remap matched, passing through. App: " ..
      appName .. " (" .. bundleID .. ")")
  end
  return false
end)



----------------------------------------------------------------------
-- WINDOW MOVEMENT / RESIZING  (Instant, no animations)
----------------------------------------------------------------------

hs.window.animationDuration = 0

local win                   = hs.window
local screen                = hs.screen

----------------------------------------------------------------------
-- ORDERED SCREENS (left → right, then top → bottom)
----------------------------------------------------------------------

local function orderedScreens()
  local screens = screen.allScreens()
  table.sort(screens, function(a, b)
    local af = a:frame()
    local bf = b:frame()
    if af.x == bf.x then
      return af.y < bf.y
    else
      return af.x < bf.x
    end
  end)
  return screens
end

----------------------------------------------------------------------
-- CYCLE SCREEN (ignores macOS adjacency, just cycles list)
----------------------------------------------------------------------

local function cycleScreen(direction)
  local w = win.frontmostWindow()
  if not w then return end

  local screens = orderedScreens()
  local current = w:screen()

  local currentIndex = nil
  for i, s in ipairs(screens) do
    if s == current then
      currentIndex = i
      break
    end
  end
  if not currentIndex then return end

  local count = #screens
  local destIndex
  if direction == "right" then
    destIndex = (currentIndex % count) + 1       -- forward wrap
  else
    destIndex = ((currentIndex - 2) % count) + 1 -- backward wrap
  end

  local dest = screens[destIndex]
  if not dest then return end

  withNoEnhancedUI(w, function()
    w:moveToScreen(dest, false, false) -- instant, no accessibility animation
  end)
end

----------------------------------------------------------------------
-- DETECT CENTERED WINDOW (for special left/right behavior)
----------------------------------------------------------------------

local function isCenteredWindow(w)
  local f        = w:frame()
  local s        = w:screen():frame()

  local hRatio   = f.h / s.h

  -- window center vs screen center
  local fCenterX = f.x + f.w / 2
  local sCenterX = s.x + s.w / 2
  local xDelta   = math.abs(fCenterX - sCenterX)

  -- treat as centered only if:
  -- - height is clearly less than full
  -- - horizontally centered (within 20px)
  return (hRatio < 0.9) and (xDelta < 20)
end

----------------------------------------------------------------------
-- GEOMETRY MOVEMENT (tiling, instant)
----------------------------------------------------------------------

local function moveToGeometry(geom)
  local w = win.frontmostWindow()
  if not w then return end

  local s = w:screen():frame()
  local f = w:frame()
  local target

  if geom == "left" then
    if isCenteredWindow(w) then
      -- first press from centered: preserve height
      target = {
        x = s.x,
        y = f.y,
        w = s.w / 2,
        h = f.h,
      }
    else
      -- second press: full-height left tile
      target = { x = s.x, y = s.y, w = s.w / 2, h = s.h }
    end
  elseif geom == "right" then
    if isCenteredWindow(w) then
      -- first press from centered: preserve height
      target = {
        x = s.x + s.w / 2,
        y = f.y,
        w = s.w / 2,
        h = f.h,
      }
    else
      -- second press: full-height right tile
      target = { x = s.x + s.w / 2, y = s.y, w = s.w / 2, h = s.h }
    end
  elseif geom == "bottom" then
    target = { x = s.x, y = s.y + s.h / 2, w = s.w, h = s.h / 2 }
  elseif geom == "max" then
    target = s
  elseif geom == "centered" then
    local scale = 0.5
    local wSize = s.w * scale * 0.8
    local hSize = s.h * scale

    target = {
      x = s.x + (s.w - wSize) / 2,
      y = s.y + (s.h - hSize) / 2,
      w = wSize,
      h = hSize,
    }
  else
    return
  end

  withNoEnhancedUI(w, function()
    w:setFrame(target, 0) -- instant
  end)
end

----------------------------------------------------------------------
-- KEYBINDS
----------------------------------------------------------------------

hs.hotkey.bind({ "cmd", "shift" }, "right", function()
  cycleScreen("right")
end)

hs.hotkey.bind({ "cmd", "shift" }, "left", function()
  cycleScreen("left")
end)

hs.hotkey.bind({ "cmd" }, "left", function()
  moveToGeometry("left")
end)

hs.hotkey.bind({ "cmd" }, "right", function()
  moveToGeometry("right")
end)

hs.hotkey.bind({ "cmd" }, "down", function()
  moveToGeometry("centered")
end)

hs.hotkey.bind({ "cmd" }, "up", function()
  moveToGeometry("max")
end)
------------------------------------------------------------
--  PER-WINDOW MINIMIZE (override ⌘⌥M)
------------------------------------------------------------
hs.hotkey.bind({ "cmd", "shift" }, "down", function()
  local w = hs.window.frontmostWindow()
  if not w then return end

  withNoEnhancedUI(w, function()
    w:minimize()
  end)
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

-- Flameshot: Cmd+Shift+S triggers capture


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


do
  local function quicklinksGenerate()
    ----------------------------------------------------------------------
    -- QUICKLINK APPS FOR RAYCAST (JSON-driven, with cleanup + icons)
    --  - Config: ~/.quicklink-apps.json
    --  - Output apps: ~/Applications/RaycastQuicklinks/*.app
    ----------------------------------------------------------------------

    local home       = os.getenv("HOME") or ""
    local configPath = home .. "/.quicklink-apps.json"
    local appDir     = home .. "/Applications/RaycastQuicklinks/"

    -- Ensure app dir exists
    os.execute("mkdir -p " .. string.format("%q", appDir))

    -- Create empty config if missing
    if not hs.fs.attributes(configPath) then
      local f = io.open(configPath, "w")
      if f then
        f:write("{}")
        f:close()
      end
      hs.alert.show("Created ~/.quicklink-apps.json — add quicklinks and reload Hammerspoon.")
    end

    -- Load user-defined quicklinks (name -> string | table)
    local function loadLinks()
      local f = io.open(configPath, "r")
      if not f then return {} end

      local json = f:read("*a") or ""
      f:close()

      if json == "" then
        return {}
      end

      local ok, data = pcall(hs.json.decode, json)
      if not ok or type(data) ~= "table" then
        hs.alert.show("Invalid JSON in ~/.quicklink-apps.json")
        return {}
      end

      return data
    end

    local links = loadLinks()
    if type(links) ~= "table" or not next(links) then
      print("[quicklinks] No quicklinks defined, nothing to generate.")
      return
    end


    ----------------------------------------------------------------------
    -- DEPENDENCY: fileicon (auto-install via Homebrew if possible)
    ----------------------------------------------------------------------

    local function findExecutable(candidates)
      for _, p in ipairs(candidates) do
        if hs.fs.attributes(p) then
          return p
        end
      end
      return nil
    end

    local function ensureFileicon()
      -- 1) Already installed?
      local existing = findExecutable({
        "/opt/homebrew/bin/fileicon",
        "/usr/local/bin/fileicon",
        "/usr/bin/fileicon",
      })
      if existing then return existing end

      -- 2) Try to install via Homebrew
      local brew = findExecutable({
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
      })

      if not brew then
        hs.alert.show("Quicklinks: Homebrew not found; cannot install 'fileicon'.")
        return nil
      end

      hs.alert.show("Quicklinks: installing 'fileicon' via Homebrew...")

      local cmd = string.format('%q install fileicon >/dev/null 2>&1', brew)
      local ok = os.execute(cmd)

      if not ok then
        hs.alert.show("Quicklinks: failed to install 'fileicon'.")
        return nil
      end

      -- 3) Re-resolve after install
      local installed = findExecutable({
        "/opt/homebrew/bin/fileicon",
        "/usr/local/bin/fileicon",
        "/usr/bin/fileicon",
      })

      if not installed then
        hs.alert.show("Quicklinks: 'fileicon' still missing after install.")
        return nil
      end

      hs.alert.show("Quicklinks: 'fileicon' installed.")
      return installed
    end

    local FILEICON = ensureFileicon()
    if not FILEICON then
      print("[quicklinks] 'fileicon' CLI not available; quicklink apps will have generic icons.")
    end

    ----------------------------------------------------------------------
    -- HELPERS
    ----------------------------------------------------------------------


    local function escapeShell(str)
      return string.format("%q", str)
    end

    local function plistEscape(str)
      str = tostring(str or "")
      str = str:gsub("&", "&amp;")
      str = str:gsub("<", "&lt;")
      str = str:gsub(">", "&gt;")
      return str
    end

    -- Fetch favicon and cache as PNG under appDir/Icons/<host>.png
    -- ---------------------------------------------------------
    -- ASYNC ICON QUEUE (non-blocking)
    -- ---------------------------------------------------------

    if _G.__quicklinkIconWorker and _G.__quicklinkIconWorker.stop then
      _G.__quicklinkIconWorker:stop()
    end
    _G.__quicklinkIconWorker = nil
    _G.__quicklinkIconQueue = {}


    local function ensureFaviconPngAsync(url, cb)
      -- Important: do not do any hs.http.get (sync). Only asyncGet.
      local host = url:match("^https?://([^/%?]+)")
      if not host then return cb(nil) end

      local iconCacheDir = appDir .. "Icons/"
      os.execute("mkdir -p " .. escapeShell(iconCacheDir))

      local pngPath = iconCacheDir .. host .. ".png"
      if hs.fs.attributes(pngPath) then
        return cb(pngPath) -- already cached
      end

      local scheme = url:match("^(https?)://") or "https"
      local faviconUrl = scheme .. "://" .. host .. "/favicon.ico"

      local function writeBody(body)
        local f = io.open(pngPath, "wb")
        if not f then return cb(nil) end
        f:write(body)
        f:close()
        cb(pngPath)
      end

      -- Try host favicon.ico
      hs.http.asyncGet(faviconUrl, nil, function(code, body)
        if code == 200 and body and #body > 0 then
          return writeBody(body)
        end

        -- Fallback: Google favicon service
        local fallback = "https://www.google.com/s2/favicons?sz=128&domain=" .. host
        hs.http.asyncGet(fallback, nil, function(code2, body2)
          if code2 == 200 and body2 and #body2 > 0 then
            return writeBody(body2)
          end
          cb(nil)
        end)
      end)
    end

    local function enqueueIconJob(appPath, url, iconOverride)
      table.insert(_G.__quicklinkIconQueue, { appPath = appPath, url = url, iconOverride = iconOverride })
    end

    local jobBusy = false

    local function startIconWorkerIfNeeded()
      if _G.__quicklinkIconWorker and _G.__quicklinkIconWorker:running() then return end

      _G.__quicklinkIconWorker = hs.timer.doEvery(0.05, function()
        if jobBusy then return end

        local job = table.remove(_G.__quicklinkIconQueue, 1)
        if not job then
          _G.__quicklinkIconWorker:stop()
          return
        end

        if not FILEICON then
          return
        end

        jobBusy = true

        local appPath = job.appPath
        local url = job.url
        local iconOverride = job.iconOverride

        local source = iconOverride
        if source and source:sub(1, 1) == "~" then
          source = home .. source:sub(2)
        end

        local function runFileiconSet(appPath2, iconPath2, done)
          -- fileicon set <appPath> <iconPath>  (async, no UI stall)
          local t = hs.task.new(FILEICON, function(exitCode, _, _)
            done(exitCode == 0)
          end, { "set", appPath2, iconPath2 })

          if not t then return done(false) end
          t:start()
        end

        local function runTouch(path)
          local t = hs.task.new("/usr/bin/touch", function() end, { path })
          if t then t:start() end
        end

        local function applyIconAsync(iconPath)
          if not iconPath or not hs.fs.attributes(iconPath) then
            jobBusy = false
            return
          end

          runFileiconSet(appPath, iconPath, function(ok)
            if ok then runTouch(appPath) end
            jobBusy = false
          end)
        end

        if source then
          applyIconAsync(source)
        else
          ensureFaviconPngAsync(url, applyIconAsync) -- async download, then async fileicon
        end
      end)
    end



    ----------------------------------------------------------------------
    -- CLEANUP OLD APPS
    ----------------------------------------------------------------------

    local desired = {}
    for name, _ in pairs(links) do
      desired[name .. ".app"] = true
    end

    for file in hs.fs.dir(appDir) do
      if file ~= "." and file ~= ".." and file:match("%.app$") then
        if not desired[file] then
          local path = appDir .. file
          os.execute("rm -rf " .. escapeShell(path))
        end
      end
    end

    ----------------------------------------------------------------------
    -- BUNDLE CREATION (minimal .app with shell script executable)
    ----------------------------------------------------------------------

    local function makeBundle(name, url, browser, appToLaunch)
      local appPath  = appDir .. name .. ".app"
      local contents = appPath .. "/Contents"
      local macOSDir = contents .. "/MacOS"

      os.execute("mkdir -p " .. escapeShell(macOSDir))

      local exeName = "run"
      local exePath = macOSDir .. "/" .. exeName

      local function dq(s)
        return (s or ""):gsub('"', '\\"')
      end

      local f = io.open(exePath, "w")
      if not f then
        print("[quicklinks] Failed to write launcher for", name)
        return nil
      end

      f:write("#!/bin/bash\n")
      f:write("set -e\n")

      if appToLaunch and appToLaunch ~= "" then
        f:write('open "' .. dq(appToLaunch) .. '"\n')
      elseif url and url ~= "" then
        f:write('URL="' .. dq(url) .. '"\n')
        f:write('BID=""\n')
        f:write('APPNAME=""\n')

        if browser and browser ~= "" then
          f:write('BROWSER="' .. dq(browser) .. '"\n')
          f:write('if [[ "$BROWSER" == *.*.* ]]; then\n')
          f:write('  BID="$BROWSER"\n')
          f:write('  open -b "$BID" "$URL"\n')
          f:write('else\n')
          f:write('  APPNAME="$BROWSER"\n')
          f:write('  open -a "$APPNAME" "$URL"\n')
          f:write('fi\n')
        else
          f:write(
            'BID="$(plutil -convert json -o - "$HOME/Library/Preferences/com.apple.LaunchServices/com.apple.launchservices.secure.plist" 2>/dev/null \\\n')
          f:write(' | /usr/bin/python3 - <<\'PY\'\n')
          f:write('import json,sys\n')
          f:write('data=json.load(sys.stdin)\n')
          f:write('handlers=data.get("LSHandlers",[])\n')
          f:write('def pick(s):\n')
          f:write('  for h in handlers:\n')
          f:write('    if h.get("LSHandlerURLScheme")==s:\n')
          f:write('      return h.get("LSHandlerRoleAll") or h.get("LSHandlerRoleViewer")\n')
          f:write('  return None\n')
          f:write('print(pick("https") or pick("http") or "")\n')
          f:write('PY\n')
          f:write(')"\n')
          f:write('if [[ -n "$BID" ]]; then\n')
          f:write('  open -b "$BID" "$URL"\n')
          f:write('else\n')
          f:write('  open "$URL"\n')
          f:write('fi\n')
        end

        f:write('sleep 0.05\n')
        f:write('if [[ -n "$BID" ]]; then\n')
        f:write('  osascript <<EOF >/dev/null 2>&1\n')
        f:write('tell application id "$BID" to activate\n')
        f:write('tell application "System Events"\n')
        f:write('  set p to first process whose bundle identifier is "$BID"\n')
        f:write('  set frontmost of p to true\n')
        f:write('end tell\n')
        f:write('EOF\n')
        f:write('elif [[ -n "$APPNAME" ]]; then\n')
        f:write('  osascript <<EOF >/dev/null 2>&1\n')
        f:write('tell application "$APPNAME" to activate\n')
        f:write('tell application "System Events" to set frontmost of process "$APPNAME" to true\n')
        f:write('EOF\n')
        f:write('fi\n')
      end

      f:close()


      os.execute("chmod +x " .. escapeShell(exePath))

      -- Info.plist (minimal, plus background-only)
      local plistPath = contents .. "/Info.plist"
      local bundleId  = "local.raycastquicklink." .. name:gsub("[^%w%.%-]", "-")

      local plist     = [[<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>]] .. plistEscape(name) .. [[</string>
  <key>CFBundleDisplayName</key>
  <string>]] .. plistEscape(name) .. [[</string>
  <key>CFBundleIdentifier</key>
  <string>]] .. plistEscape(bundleId) .. [[</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>]] .. exeName .. [[</string>
  <key>LSBackgroundOnly</key>
  <true/>
</dict>
</plist>
]]

      local pf        = io.open(plistPath, "w")
      if pf then
        pf:write(plist)
        pf:close()
      end

      return appPath
    end

    ----------------------------------------------------------------------
    -- GENERATE / REFRESH APPS
    ----------------------------------------------------------------------

    for name, entry in pairs(links) do
      local url
      local browser
      local iconOverride
      local appToLaunch

      if type(entry) == "table" then
        url          = entry.url
        browser      = entry.browser
        iconOverride = entry.icon
        appToLaunch  = entry.app
      elseif type(entry) == "string" then
        url = entry
      else
        print("[quicklinks] Invalid link entry for:", name)
        goto continue
      end

      if (url and url ~= "") or (appToLaunch and appToLaunch ~= "") then
        local appPath = makeBundle(name, url, browser, appToLaunch)
        if appPath then
          enqueueIconJob(appPath, url, iconOverride)
          startIconWorkerIfNeeded()
        end
      end

      ::continue::
    end

  end
  hs.timer.doAfter(0.2, quicklinksGenerate)
end

hs_alert.show("Windows-like Remapping Active (v2.2 - Global Shortcuts & Mouse Support)")
