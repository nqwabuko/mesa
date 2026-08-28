-- ~/.hammerspoon/init.lua
--
-- Calm, app-agnostic window layouts. Three intentions plus an automatic meeting
-- layout. Master-stack and grid reflow with the number of windows (Hyprland-style),
-- so you pick by intention, not by memorising modes.
--
--   focus       (alt-cmd-f) : ONE app, centered; cmd-tab between all
--   zen         (alt-cmd-g) : the same, but a NARROW centered column — most of the
--                             ultrawide goes to wallpaper. One thing, deliberately small.
--   split       (alt-cmd-w) : the front TWO apps side by side; everything else folds behind
--   meeting     (alt-cmd-c) : the meeting shape — meeting window (or Zoom's calendar when
--                             there is no meeting) top-left, Slack below, FOCUSED app big
--                             right. Cycle the big pane by focusing a window and pressing.
--   control room(alt-cmd-r) : the SAME shape, right pane widened for reading (email, docs).
--                             Only the divider moves; panes never change places. On the
--                             ultrawide it sits in a centered column, not full bleed.
--   grid        (alt-cmd-e) : ALL apps in a balanced grid (2 -> side by side, 4 -> 2x2, 3 -> 2+1)
--   meeting     (alt-cmd-m) : same as alt-cmd-c; also auto on a Zoom/Teams meeting
--                             (laptop = single window, no room for three panes)
--
--   +--------+--------+     +--------+--------+     +-----+-----------+   +---+-------------+
--   |        |        |     |        |        |     | mtg |           |   |mtg|             |
--   |   A    |   B    |     |   one window    |     +-----+  focused  |   +---+   focused   |
--   |        |        |     |   (cmd-tab)     |     |slack|   (big)   |   |slk|    (big)    |
--   +--------+--------+     +--------+--------+     +-----+-----------+   +---+-------------+
--          split                  focus                meeting               control room
--
--   +------+--------+------+
--   |      |  one   |      |     zen: same single-window paradigm as focus, just a
--   |      | window |      |          narrower column. On the ultrawide that is
--   +------+--------+------+          ~1600px instead of ~2100px.
--             zen
--
-- Jumps: alt-cmd s/a/v/z -> Slack / Arc / VS Code / Zoom.
-- Diagnostics: alt-cmd-9 screen info, alt-cmd-0 Zoom/Teams window titles.
--
-- Requires Accessibility permission. Reload after edits: quit + `open -a Hammerspoon`.

hs.window.animationDuration = 0
hs.autoLaunch(true)
pcall(function() require("hs.ipc").cliInstall("/opt/homebrew") end)  -- enable `hs -c` CLI

-- Shared tiling look (split + grid)
local TILE_PAD = 60      -- outer margin around a tiled layout
local TILE_GAP = 20      -- gap between tiled windows

-- Focal (single-app centered) frame, per display profile
local NORMAL_PAD_TOP  = 100
local NORMAL_PAD_SIDE = 250
local NORMAL_BOTTOM   = 100
local LAPTOP_PAD      = 16       -- built-in screen: near-maximise
local ULTRAWIDE_MIN_W = 3200     -- >= this wide => curved ultrawide ("noc")
local NOC_CENTER_PAD  = 640      -- side margin for a single app on the ultrawide (~2100px)

-- Zen: focus, dialled down. Fixed column WIDTH per profile (not a margin), so the
-- wider the display the more it disappears — the point is that it reads as small on
-- the curved ultrawide, where plain focus is still 2100px of window.
local ZEN = {
  laptop = { w = 1100, pad = 40  },
  desk   = { w = 1250, pad = 120 },
  noc    = { w = 1600, pad = 140 },   -- measured: Gmail in Arc chops below ~1550
}

-- Three-pane shape (desk/noc)
local GAP = 12

-- Control room is the READING shape, so on a big display it doesn't have to fill
-- it. Fixed content WIDTH per profile (the ZEN idea again): the wider the display,
-- the more of it stays empty. nil = full bleed, as the meeting shape always is.
local CONTROL_BOX = {
  laptop = nil,
  desk   = nil,
  noc    = { w = 2520, padY = 110, gap = 20 },  -- right pane lands at 1700
}

local BUNDLE = {
  slack  = "com.tinyspeck.slackmacgap",
  arc    = "company.thebrowser.Browser",
  zoom   = "us.zoom.xos",
  teams  = "com.microsoft.teams2",
  vscode = "com.microsoft.VSCode",
}

-- Apps that can host a meeting. Whichever has a live meeting/share window gets
-- placed in the meeting slot. `pat` = lowercase title substrings meaning "live".
-- (Teams patterns are a first guess — tune from the alt-cmd-0 diagnostic log.)
local MEETING_APPS = {
  { bundle = "us.zoom.xos",          pat = { "meeting", "share", "sharing", "floating video", "annotation", "as_toolbar" } },
  -- Teams names a meeting window "<subject> | Microsoft Teams". So: match ANY Teams
  -- window, then exclude the known idle tabs. Anything left is a live meeting.
  { bundle = "com.microsoft.teams2", pat = { "| microsoft teams" },
    exclude = { "activity |", "chat |", "teams |", "calendar |", "calls |", "files |",
                "onedrive |", "apps |", "store |", "settings |", "search |",
                "communities |", "community |", "help |" } },
}

-- ---------------------------------------------------------------------------
-- Window lookup
-- ---------------------------------------------------------------------------

local function appWindows(bundle)
  local app = hs.application.get(bundle)
  return app and app:allWindows() or {}
end

local function mainWindowOf(bundle)
  for _, w in ipairs(appWindows(bundle)) do
    if w:isStandard() then return w end
  end
  return nil
end

-- All "real" windows on a screen, front-to-back. Tiny utility windows (Fathom
-- recorder, Teams compact view) are filtered out so layouts never yank them.
local MIN_TILE_W, MIN_TILE_H = 400, 300
local function realWindowsOn(scr)
  local out = {}
  for _, w in ipairs(hs.window.orderedWindows()) do
    local f = w:frame()
    if w:isStandard() and w:isVisible() and f.w >= MIN_TILE_W and f.h >= MIN_TILE_H
       and w:screen():id() == scr:id() then
      out[#out + 1] = w
    end
  end
  return out
end

local function focusedScreen()
  local w = hs.window.focusedWindow()
  return (w and w:screen()) or hs.screen.mainScreen()
end

-- ---------------------------------------------------------------------------
-- Meeting detection (Zoom / Teams)
-- ---------------------------------------------------------------------------

local function titleMatchesAny(title, pats)
  local t = (title or ""):lower()
  if t == "" then return false end
  for _, p in ipairs(pats) do
    if t:find(p, 1, true) then return true end
  end
  return false
end

-- A window is a live meeting for app `m` if its title matches a `pat` and (if the
-- app has an `exclude` list, e.g. Teams' idle tabs) matches none of the excludes.
local function windowIsMeeting(title, m)
  if not titleMatchesAny(title, m.pat) then return false end
  if m.exclude then
    local t = (title or ""):lower()
    for _, e in ipairs(m.exclude) do
      if t:find(e, 1, true) then return false end
    end
  end
  return true
end

-- Returns (window, bundle) for the live meeting, or nil.
local function activeMeeting()
  for _, m in ipairs(MEETING_APPS) do
    for _, w in ipairs(appWindows(m.bundle)) do
      if windowIsMeeting(w:title(), m) then return w, m.bundle end
    end
  end
  return nil
end

local function meetingActive() return activeMeeting() ~= nil end

local function placementWindow(bundle)
  local fallback
  for _, w in ipairs(appWindows(bundle)) do
    if w:isStandard() and w:isVisible() then
      local f = w:frame()
      if f.w >= 400 and f.h >= 300 then return w end
      fallback = fallback or w
    end
  end
  return fallback
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

local function place(win, x, y, w, h)
  if win then win:setFrame(hs.geometry.rect(x, y, w, h)) end
end

local function screenProfile(screen)
  local name = (screen:name() or ""):lower()
  local w = screen:frame().w
  if name:find("built%-in") or name:find("color lcd") or w <= 1800 then
    return "laptop"
  elseif w >= ULTRAWIDE_MIN_W then
    return "noc"
  end
  return "desk"
end

-- The centered "single focal app" frame for a screen, sized to its profile.
local function focalFrame(screen)
  local sf = screen:frame()
  local p = screenProfile(screen)
  if p == "laptop" then
    return hs.geometry.rect(sf.x + LAPTOP_PAD, sf.y + LAPTOP_PAD,
                            sf.w - 2 * LAPTOP_PAD, sf.h - 2 * LAPTOP_PAD)
  elseif p == "noc" then
    return hs.geometry.rect(sf.x + NOC_CENTER_PAD, sf.y + NORMAL_PAD_TOP,
                            sf.w - 2 * NOC_CENTER_PAD, sf.h - NORMAL_PAD_TOP - NORMAL_BOTTOM)
  end
  return hs.geometry.rect(sf.x + NORMAL_PAD_SIDE, sf.y + NORMAL_PAD_TOP,
                          sf.w - 2 * NORMAL_PAD_SIDE, sf.h - NORMAL_PAD_TOP - NORMAL_BOTTOM)
end

-- The zen frame: a centered column of fixed width, never wider than the focal frame
-- (so zen is always the calmer of the two, whatever the display).
local function zenFrame(screen)
  local sf = screen:frame()
  local z  = ZEN[screenProfile(screen)]
  local w  = math.min(z.w, focalFrame(screen).w)
  local h  = sf.h - 2 * z.pad
  return hs.geometry.rect(sf.x + (sf.w - w) / 2, sf.y + z.pad, w, h)
end

-- ---------------------------------------------------------------------------
-- The three layouts
-- ---------------------------------------------------------------------------

-- One-window paradigm: every window shares a single centered frame; cmd-tab cycles
-- them. focus uses the focal frame, zen the narrower column.
local function layoutSingle(frameFn)
  local scr = hs.screen.mainScreen()
  local f = frameFn(scr)
  for _, w in ipairs(realWindowsOn(scr)) do w:setFrame(f) end
  local focused = hs.window.focusedWindow()
  if focused then focused:focus() end
end

local function layoutFocus() layoutSingle(focalFrame) end
local function layoutZen()   layoutSingle(zenFrame) end

-- Split: the two front-most windows (the top of your cmd-tab queue) go side by
-- side; every other window folds behind them, so it feels like only two are open.
local function layoutSplit()
  local scr = focusedScreen()
  local wins = realWindowsOn(scr)
  if #wins == 0 then return end
  local sf = scr:frame()
  local h  = sf.h - 2 * TILE_PAD
  local usableW = sf.w - 2 * TILE_PAD - TILE_GAP
  local halfW = usableW / 2
  local leftRect  = hs.geometry.rect(sf.x + TILE_PAD, sf.y + TILE_PAD, halfW, h)
  local rightRect = hs.geometry.rect(sf.x + TILE_PAD + halfW + TILE_GAP, sf.y + TILE_PAD, halfW, h)

  if #wins == 1 then
    wins[1]:setFrame(hs.geometry.rect(sf.x + TILE_PAD, sf.y + TILE_PAD, usableW + TILE_GAP, h))
    wins[1]:focus()
    return
  end

  -- front two, keeping their current left/right order so they don't jump sides
  local left, right = wins[1], wins[2]
  if wins[2]:frame().x < wins[1]:frame().x then left, right = wins[2], wins[1] end

  -- fold everyone else behind the left pane (hidden), then place + raise the two
  for i = 3, #wins do wins[i]:setFrame(leftRect) end
  left:setFrame(leftRect)
  right:setFrame(rightRect)
  left:raise(); right:raise()
end

-- Grid: all windows in a balanced grid. cols = ceil(sqrt(n)); each row stretches
-- to full width so a partial last row fills nicely (3 -> 2 over 1, 4 -> 2x2).
local function layoutGrid()
  local scr = focusedScreen()
  local wins = realWindowsOn(scr)
  if #wins == 0 then return end
  table.sort(wins, function(a, b)
    local af, bf = a:frame(), b:frame()
    if math.abs(af.y - bf.y) > 100 then return af.y < bf.y end
    return af.x < bf.x
  end)

  local sf = scr:frame()
  local n = #wins
  local cols = math.ceil(math.sqrt(n))
  local rows = math.ceil(n / cols)
  local h = sf.h - 2 * TILE_PAD
  local cellH = (h - (rows - 1) * TILE_GAP) / rows

  local idx = 1
  for r = 0, rows - 1 do
    local rowCount = math.min(cols, n - r * cols)
    local cellW = (sf.w - 2 * TILE_PAD - (rowCount - 1) * TILE_GAP) / rowCount
    for c = 0, rowCount - 1 do
      local w = wins[idx]; idx = idx + 1
      w:setFrame(hs.geometry.rect(sf.x + TILE_PAD + c * (cellW + TILE_GAP),
                                  sf.y + TILE_PAD + r * (cellH + TILE_GAP), cellW, cellH))
    end
  end
end

-- ---------------------------------------------------------------------------
-- The three-pane shape: meeting proportions and control-room proportions
-- ---------------------------------------------------------------------------
-- One shape, two widths. Left column: the live meeting window (or Zoom's calendar
-- when there is no meeting) on top, Slack below. Right: whatever you are focused
-- on, big. alt-cmd-c gives meeting proportions, alt-cmd-r widens the right pane
-- for reading. Nothing changes places between the two — only the divider moves,
-- and on the ultrawide the whole control-room shape pulls into a centered box.

local MEETING_FRACTION = 0.60   -- right-pane width share: meeting proportions
local CONTROL_FRACTION = 0.68   -- right-pane width share: control room (wider)
local TOP_LEFT_SHARE   = 0.40   -- what the top-left pane ASKS for; apps with a
                                -- taller minimum get measured (see threePane)

-- box (optional) centers a content box of fixed width instead of filling the
-- screen. Without one this is the original full-bleed geometry, to the pixel.
local function columns(mainFraction, box)
  local sf   = hs.screen.mainScreen():frame()
  local gap  = box and box.gap  or GAP
  local padY = box and box.padY or GAP
  local boxW = math.min(box and box.w or math.huge, sf.w - 2 * gap)
  local boxX = sf.x + (sf.w - boxW) / 2

  local usableW = boxW - gap
  local rightW  = usableW * mainFraction
  local leftW   = usableW - rightW
  return {
    sf = sf, gap = gap, leftW = leftW, rightW = rightW, fullH = sf.h - 2 * padY,
    leftX = boxX, rightX = boxX + leftW + gap, topY = sf.y + padY,
  }
end

-- Two stacked windows in the left column, one full-height window beside them, and
-- every other window folded behind that right pane.
--
-- The top pane is placed FIRST and then measured. Zoom's calendar refuses to go
-- below ~650px (Teams has its own floor), so asking for less silently leaves the
-- window taller than its slot and it swallows whatever sits below. Reading the
-- frame back after setFrame gives the height the app actually accepted, and the
-- bottom pane takes the true remainder — nothing per-app to hard-code.
local function threePane(scr, topWin, botWin, rightWin, mainFraction, box)
  local c = columns(mainFraction, box)
  local avail = c.fullH - c.gap

  local topH = avail * TOP_LEFT_SHARE
  place(topWin, c.leftX, c.topY, c.leftW, topH)
  if topWin then topH = topWin:frame().h end          -- what the app actually took
  local botH = avail - topH
  if botH > 0 then place(botWin, c.leftX, c.topY + topH + c.gap, c.leftW, botH) end

  local rightRect = hs.geometry.rect(c.rightX, c.topY, c.rightW, c.fullH)
  if rightWin then rightWin:setFrame(rightRect) end

  local keep = {}
  for _, w in ipairs({ topWin, botWin, rightWin }) do if w then keep[w:id()] = true end end
  for _, w in ipairs(realWindowsOn(scr)) do
    if not keep[w:id()] then w:setFrame(rightRect) end
  end
  for _, w in ipairs({ topWin, botWin, rightWin }) do if w then w:raise() end end
end

-- The top-left window: the live meeting if there is one, else Zoom's calendar — so
-- the same keys give the same shape in a meeting and out of one.
local function topLeftWindow()
  local meet, mtgBundle = activeMeeting()
  if meet and mtgBundle then
    -- If what matched isn't sizeable (e.g. a Zoom share toolbar), use a real window.
    local f = meet:frame()
    if not (meet:isStandard() and f.w >= 400 and f.h >= 300) then
      meet = placementWindow(mtgBundle) or meet
    end
    return meet
  end
  return mainWindowOf(BUNDLE.zoom)
end

local function layoutThreePane(mainFraction, box)
  local scr = hs.screen.mainScreen()

  -- Laptop: no room for three panes. Single-window paradigm, meeting app in front.
  if screenProfile(scr) == "laptop" then
    layoutFocus()
    local front = topLeftWindow()
    if front then front:focus() end
    return
  end

  -- Zoom often sits windowless in the menu bar. Summon it, then lay out once.
  local top = topLeftWindow()
  if not top then
    hs.application.launchOrFocusByBundleID(BUNDLE.zoom)
    hs.timer.doAfter(0.8, function()
      if topLeftWindow() then layoutThreePane(mainFraction, box) end
    end)
    return
  end

  local slack = mainWindowOf(BUNDLE.slack)
  -- The left column already owns the meeting window and Slack, so if one of those
  -- is focused the big pane falls back to Arc rather than duplicating a window.
  local main = hs.window.focusedWindow()
  if not main or main:id() == top:id() or (slack and main:id() == slack:id()) then
    main = mainWindowOf(BUNDLE.arc)
  end

  threePane(scr, top, slack, main, mainFraction, box)
  if main then main:focus() end
end

local function layoutMeeting()     layoutThreePane(MEETING_FRACTION) end
local function layoutControlRoom()
  layoutThreePane(CONTROL_FRACTION, CONTROL_BOX[screenProfile(hs.screen.mainScreen())])
end

-- ---------------------------------------------------------------------------
-- Meeting watcher: 2s poll tracks meeting state both ways; share windows count
-- as "live" so a screen-share doesn't false-flip to focus. windowCreated gives
-- instant entry. On end, revert to focus and raise Slack.
-- ---------------------------------------------------------------------------

local inMeeting   = false
local absentTicks = 0
local ABSENT_LIMIT = 3   -- ~6s of no meeting/share window before reverting

local function enterMeeting()
  if inMeeting then return end
  inMeeting = true
  hs.timer.doAfter(0.4, layoutMeeting)
end

local function exitMeeting()
  if not inMeeting then return end
  inMeeting = false
  layoutFocus()
  local slack = mainWindowOf(BUNDLE.slack)
  if slack then slack:focus() end
end

hs.timer.doEvery(2, function()
  if meetingActive() then
    absentTicks = 0
    enterMeeting()
  elseif inMeeting then
    absentTicks = absentTicks + 1
    if absentTicks >= ABSENT_LIMIT then exitMeeting() end
  end
end)

for _, appName in ipairs({ "zoom.us", "Microsoft Teams" }) do
  hs.window.filter.new(false):setAppFilter(appName, {})
    :subscribe(hs.window.filter.windowCreated, function()
      if meetingActive() then absentTicks = 0; enterMeeting() end
    end)
end

-- ---------------------------------------------------------------------------
-- Hotkeys
-- ---------------------------------------------------------------------------

hs.hotkey.bind({ "alt", "cmd" }, "f", layoutFocus)     -- one focal window (cmd-tab between all)
hs.hotkey.bind({ "alt", "cmd" }, "g", layoutZen)       -- same, narrower: a zen column
hs.hotkey.bind({ "alt", "cmd" }, "w", layoutSplit)     -- front two apps side by side, rest folded behind
hs.hotkey.bind({ "alt", "cmd" }, "c", layoutMeeting)     -- meeting proportions on demand
hs.hotkey.bind({ "alt", "cmd" }, "r", layoutControlRoom) -- same shape, right pane widened for reading
hs.hotkey.bind({ "alt", "cmd" }, "e", layoutGrid)        -- balanced grid of all windows
hs.hotkey.bind({ "alt", "cmd" }, "m", layoutMeeting)     -- meeting layout (also auto)

local function focusApp(bundleID)
  return function() hs.application.launchOrFocusByBundleID(bundleID) end
end
hs.hotkey.bind({ "alt", "cmd" }, "s", focusApp(BUNDLE.slack))
hs.hotkey.bind({ "alt", "cmd" }, "a", focusApp(BUNDLE.arc))
hs.hotkey.bind({ "alt", "cmd" }, "v", focusApp(BUNDLE.vscode))
hs.hotkey.bind({ "alt", "cmd" }, "z", focusApp(BUNDLE.zoom))

-- Diagnostic: dump Zoom + Teams window titles (use mid meeting/share to tune matchers).
local ZOOM_LOG = os.getenv("HOME") .. "/.hammerspoon/zoom-titles.log"
hs.hotkey.bind({ "alt", "cmd" }, "0", function()
  local parts = {}
  for _, b in ipairs({ { "Zoom", BUNDLE.zoom }, { "Teams", BUNDLE.teams } }) do
    local titles = {}
    for _, w in ipairs(appWindows(b[2])) do
      titles[#titles + 1] = string.format('  "%s" [std=%s %dx%d]',
        (w:title() or ""), tostring(w:isStandard()), w:frame().w, w:frame().h)
    end
    parts[#parts + 1] = b[1] .. ":\n" .. (#titles > 0 and table.concat(titles, "\n") or "  (none)")
  end
  local body = table.concat(parts, "\n")
  hs.alert.show(body, 6)
  local f = io.open(ZOOM_LOG, "a")
  if f then f:write("=== " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n" .. body .. "\n"); f:close() end
end)

-- Diagnostic: focused screen name, resolution, detected profile.
hs.hotkey.bind({ "alt", "cmd" }, "9", function()
  local s = focusedScreen()
  local f = s:frame()
  local msg = string.format("Screen: %s\n%dx%d  (profile: %s)",
    s:name() or "?", math.floor(f.w), math.floor(f.h), screenProfile(s))
  hs.alert.show(msg, 6)
end)

hs.alert.show("Window layouts loaded")
