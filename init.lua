-- ~/.hammerspoon/init.lua
--
-- Calm, app-agnostic window layouts. Three intentions plus an automatic meeting
-- layout. Master-stack and grid reflow with the number of windows (Hyprland-style),
-- so you pick by intention, not by memorising modes.
--
--   focus     (alt-cmd-f) : ONE app, centered; cmd-tab between all
--   split     (alt-cmd-w) : the front TWO apps side by side; everything else folds behind
--   dashboard (alt-cmd-c) : "control room" — FOCUSED app big on the right; next two on the
--                           left (bottom taller, top smaller); others behind. Cycle by focus + press.
--   grid      (alt-cmd-e) : ALL apps in a balanced grid (2 -> side by side, 4 -> 2x2, 3 -> 2+1)
--   meeting   (alt-cmd-m) : auto on a Zoom/Teams meeting; desk = 3-pane, laptop = single window
--
--   +--------+--------+     +--------+--------+     +-----+------------+     +----+----+
--   |        |        |     |        |        |     | TL  |            |     | A  | B  |
--   |   A    |   B    |     |   one window    |     +-----+   focused  |     +----+----+
--   |        |        |     |   (cmd-tab)     |     | BL  |   (big)    |     | C  | D  |
--   +--------+--------+     +--------+--------+     +-----+------------+     +----+----+
--          split                  focus                 dashboard               grid
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

-- Meeting 3-pane (desk/noc)
local GAP            = 12
local ARC_FRACTION   = 0.60      -- Arc's width share (right pane)
local SLACK_FRACTION = 0.60      -- Slack's share of the left column
local MEETING_MIN_H  = 680       -- meeting-window min-height floor (Zoom ~650, Teams ~669)

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

-- ---------------------------------------------------------------------------
-- The three layouts
-- ---------------------------------------------------------------------------

-- Focus: all windows share one centered focal frame; cmd-tab cycles them.
local function layoutFocus()
  local scr = hs.screen.mainScreen()
  local f = focalFrame(scr)
  for _, w in ipairs(realWindowsOn(scr)) do w:setFrame(f) end
  local focused = hs.window.focusedWindow()
  if focused then focused:focus() end
end

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

-- Workstation dashboard: the FOCUSED window is the big main pane on the right; the
-- next two windows sit on the left (bottom slightly taller, top smaller); any others
-- fold behind the main. Cycle by focusing a window and pressing again -> it goes big.
-- (The meeting shape, minus the meeting; app-agnostic.)
local DASH_MAIN_FRACTION   = 0.60   -- big-right pane width share
local DASH_BOTTOM_FRACTION = 0.55   -- bottom-left height share (a touch taller than top-left)
local function layoutDashboard()
  local scr = focusedScreen()
  local wins = realWindowsOn(scr)
  if #wins == 0 then return end
  local sf = scr:frame()
  local h  = sf.h - 2 * TILE_PAD

  if #wins == 1 then
    wins[1]:setFrame(hs.geometry.rect(sf.x + TILE_PAD, sf.y + TILE_PAD, sf.w - 2 * TILE_PAD, h))
    wins[1]:focus()
    return
  end

  local focused = hs.window.focusedWindow()
  local big = wins[1]
  if focused then for _, w in ipairs(wins) do if w:id() == focused:id() then big = w; break end end end
  local rest = {}
  for _, w in ipairs(wins) do if w:id() ~= big:id() then rest[#rest + 1] = w end end

  local usableW = sf.w - 2 * TILE_PAD - TILE_GAP
  local rightW  = usableW * DASH_MAIN_FRACTION
  local leftW   = usableW - rightW
  local leftX   = sf.x + TILE_PAD
  local rightX  = leftX + leftW + TILE_GAP
  local topY    = sf.y + TILE_PAD
  local botH    = (h - TILE_GAP) * DASH_BOTTOM_FRACTION
  local topH    = (h - TILE_GAP) - botH

  local bigRect = hs.geometry.rect(rightX, topY, rightW, h)
  local blRect  = hs.geometry.rect(leftX, topY + topH + TILE_GAP, leftW, botH)  -- bottom-left, taller
  local tlRect  = hs.geometry.rect(leftX, topY, leftW, topH)                    -- top-left, smaller

  big:setFrame(bigRect)
  if rest[1] then rest[1]:setFrame(blRect) end
  if rest[2] then rest[2]:setFrame(tlRect) end
  for i = 3, #rest do rest[i]:setFrame(bigRect) end   -- fold extras behind the main
  if rest[2] then rest[2]:raise() end
  if rest[1] then rest[1]:raise() end
  big:raise(); big:focus()
end

-- ---------------------------------------------------------------------------
-- Meeting layout (Zoom / Teams) — kept as-is; auto-triggered by the watcher below
-- ---------------------------------------------------------------------------

local function columns()
  local sf = hs.screen.mainScreen():frame()
  local usableW = sf.w - 3 * GAP
  local arcW  = usableW * ARC_FRACTION
  local leftW = usableW - arcW
  return {
    sf = sf, leftW = leftW, arcW = arcW, fullH = sf.h - 2 * GAP,
    leftX = sf.x + GAP, rightX = sf.x + GAP + leftW + GAP, topY = sf.y + GAP,
  }
end

local function layoutMeeting()
  local scr   = hs.screen.mainScreen()
  local slack = mainWindowOf(BUNDLE.slack)
  local arc   = mainWindowOf(BUNDLE.arc)
  -- The live meeting window (Teams subject window / Zoom meeting window). If what
  -- matched isn't sizeable (e.g. a Zoom share toolbar), fall back to a real window.
  local meet, mtgBundle = activeMeeting()
  if meet and mtgBundle then
    local f = meet:frame()
    if not (meet:isStandard() and f.w >= 400 and f.h >= 300) then
      meet = placementWindow(mtgBundle) or meet
    end
  end

  -- Laptop: single-window paradigm, meeting app maximised in front.
  if screenProfile(scr) == "laptop" then
    local f = focalFrame(scr)
    for _, w in ipairs(realWindowsOn(scr)) do w:setFrame(f) end
    local front = meet or placementWindow(BUNDLE.zoom)
    if front then front:focus() end
    return
  end

  -- Desk / NOC: 3-pane. Meeting video top-left (near camera), Slack below, Arc right.
  local c = columns()
  local avail  = c.sf.h - 3 * GAP
  local slackH = avail * SLACK_FRACTION
  local zoomH  = avail - slackH
  if zoomH < MEETING_MIN_H then
    zoomH  = math.min(MEETING_MIN_H, avail)
    slackH = avail - zoomH
  end
  local topWin
  if meet then
    topWin = meet
    place(meet,  c.leftX, c.topY,               c.leftW, zoomH)
    place(slack, c.leftX, c.topY + zoomH + GAP, c.leftW, slackH)
  else
    topWin = mainWindowOf(BUNDLE.zoom)
    place(slack,  c.leftX, c.topY,                c.leftW, slackH)
    place(topWin, c.leftX, c.topY + slackH + GAP, c.leftW, zoomH)
  end
  place(arc, c.rightX, c.topY, c.arcW, c.fullH)

  -- Fold every other window behind Arc.
  local arcRect = hs.geometry.rect(c.rightX, c.topY, c.arcW, c.fullH)
  local keep = {}
  for _, w in ipairs({ topWin, slack, arc }) do if w then keep[w:id()] = true end end
  for _, w in ipairs(realWindowsOn(scr)) do
    if not keep[w:id()] then w:setFrame(arcRect) end
  end
  for _, w in ipairs({ topWin, slack, arc }) do if w then w:raise() end end
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
hs.hotkey.bind({ "alt", "cmd" }, "w", layoutSplit)     -- front two apps side by side, rest folded behind
hs.hotkey.bind({ "alt", "cmd" }, "c", layoutDashboard) -- control room / dashboard: focused = big right; cycle by focusing + pressing
hs.hotkey.bind({ "alt", "cmd" }, "e", layoutGrid)      -- balanced grid of all windows
hs.hotkey.bind({ "alt", "cmd" }, "m", layoutMeeting)   -- meeting layout (also auto)

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
