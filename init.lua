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
-- Split carries a stack: everything that isn't in the two panes folds behind the
-- left one, and can be rotated into a pane rather than hunted for with cmd-tab.
--
--   alt-cmd-] / [ : rotate the FOCUSED pane forward / back through the stack
--   alt-cmd-x     : swap the two panes (nothing resizes)
--   alt-cmd-h / l : put the keyboard in the left / right pane
--   alt-cmd-= / - : grow / shrink the FOCUSED pane by one detent
--
-- Jumps: alt-cmd s/a/v/z -> Slack / Arc / VS Code / Zoom.
-- Diagnostics: alt-cmd-9 screen info, alt-cmd-0 Zoom/Teams window titles.
-- Cheatsheet: alt-cmd-/ lists every binding on screen (escape or click to close).
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

-- Split on a big display, same "a width, not a margin" idea as zen and control
-- room: two panes of a fixed WIDTH in a centered box, so the wider the display the
-- more of it stays wallpaper. paneW here is ZEN.noc.w, i.e. a split on the
-- ultrawide is literally two zen columns side by side. nil = full bleed.
local SPLIT_BOX = {
  laptop = nil,
  desk   = nil,
  noc    = { paneW = 1600, padY = 100 },
}

-- Divider positions for split. Detents rather than a free drag, so moving the
-- divider stays a shift of PROPORTIONS (as control room is to meeting) instead of
-- a resize you have to aim. Each value is the left pane's share of the usable
-- width; golden-ish either side of an even split.
local SPLIT_RATIOS = { 0.38, 0.5, 0.62 }
local MIN_PANE_W   = 560     -- a detent that would go under this is not offered

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

-- Split: two panes and a stack.
--
-- This is the only layout that remembers anything between presses, because
-- cycling needs something to cycle. The memory is a HINT, never the truth: every
-- operation re-resolves it against the live windows, and anything that has closed,
-- moved screen or stopped being tileable simply drops out and is topped up from
-- the front of the window order. So a stale session decays back into the plain
-- "front two, everything else behind" split instead of getting stuck.

local split = { screenId = nil, leftId = nil, rightId = nil, stack = {},
                stackSide = "left" }

-- The content box a split lives in: the whole screen inside TILE_PAD, or the
-- centered box SPLIT_BOX asks for. The box does not change when the divider does.
local function splitBox(scr)
  local sf   = scr:frame()
  local box  = SPLIT_BOX[screenProfile(scr)]
  local padY = box and box.padY or TILE_PAD
  local boxW = sf.w - 2 * TILE_PAD
  if box then boxW = math.min(2 * box.paneW + TILE_GAP, boxW) end
  return sf.x + (sf.w - boxW) / 2, sf.y + padY, boxW, sf.h - 2 * padY
end

-- left rect, right rect, and the whole-box rect used when there is only one window.
-- `ratio` is the left pane's share of the usable width; nil means an even split.
local function splitRects(scr, ratio)
  local x, y, boxW, h = splitBox(scr)
  local usableW = boxW - TILE_GAP
  local leftW   = usableW * (ratio or 0.5)
  return hs.geometry.rect(x, y, leftW, h),
         hs.geometry.rect(x + leftW + TILE_GAP, y, usableW - leftW, h),
         hs.geometry.rect(x, y, boxW, h)
end

-- The detents that leave BOTH panes usable on this screen. On the laptop the
-- narrow ones drop out, so nudging simply stops rather than handing you a pane
-- too thin to work in.
local function splitDetents(scr)
  local _, _, boxW = splitBox(scr)
  local usableW = boxW - TILE_GAP
  local out = {}
  for _, r in ipairs(SPLIT_RATIOS) do
    if usableW * r >= MIN_PANE_W and usableW * (1 - r) >= MIN_PANE_W then
      out[#out + 1] = r
    end
  end
  return #out > 0 and out or { 0.5 }
end

-- Resolve the remembered split against what is actually on screen.
local function splitSession(scr)
  local wins = realWindowsOn(scr)                     -- front-to-back
  if #wins == 0 then return nil end

  local fresh, used, byId = split.screenId ~= scr:id(), {}, {}
  for _, w in ipairs(wins) do byId[w:id()] = w end
  if fresh then split.ratio, split.stackSide = nil, nil end  -- a new screen starts over

  local function claim(id)
    if fresh or not id or used[id] then return nil end
    local w = byId[id]
    if w then used[id] = true end
    return w
  end

  local left, right = claim(split.leftId), claim(split.rightId)

  -- Whatever is unclaimed, front-to-back: fills an empty pane, then forms the stack.
  local rest = {}
  for _, w in ipairs(wins) do if not used[w:id()] then rest[#rest + 1] = w end end

  -- A brand-new split takes the front two and keeps their current left/right
  -- order, so neither window jumps sides the first time you press alt-cmd-w.
  if not left and not right and #rest >= 2 then
    left, right = rest[1], rest[2]
    if right:frame().x < left:frame().x then left, right = right, left end
    used[left:id()], used[right:id()] = true, true
  else
    for _, w in ipairs(rest) do
      if not used[w:id()] then
        if     not left  then left  = w; used[w:id()] = true
        elseif not right then right = w; used[w:id()] = true end
      end
    end
  end

  -- The stack keeps its remembered order (that is what makes rotation stable);
  -- dead entries drop out and windows opened since join the back.
  local stack = {}
  for _, id in ipairs(split.stack) do
    local w = claim(id)
    if w then stack[#stack + 1] = w end
  end
  for _, w in ipairs(wins) do
    if not used[w:id()] then used[w:id()] = true; stack[#stack + 1] = w end
  end

  -- If the keyboard is on a stacked window (you cmd-tabbed to it, so it is sitting
  -- on top of whichever pane the stack lives under), then that IS that pane now.
  -- Without this the model and the thing you are looking at disagree, and the next
  -- rotate starts from somewhere you can't see.
  local stackSide = split.stackSide or "left"
  local host = (stackSide == "right") and right or left
  local f = hs.window.focusedWindow()
  if f and host then
    for i, w in ipairs(stack) do
      if w:id() == f:id() then
        stack[i] = host
        if stackSide == "right" then right = w else left = w end
        break
      end
    end
  end

  return { left = left, right = right, stack = stack, ratio = split.ratio,
           stackSide = stackSide }
end

-- Move the windows. Says nothing about what is remembered — commitSplit does
-- that — so the caller decides when a layout becomes the new session.
local function renderSplit(scr, s)
  local leftRect, rightRect, fullRect = splitRects(scr, s.ratio)

  if not s.right then
    if s.left then s.left:setFrame(fullRect); s.left:focus() end
  else
    -- The stack sits under whichever pane you last rotated, so cycling only ever
    -- redraws that half of the screen and cmd-tab still reads as "bring the next
    -- thing into the slot I am working in".
    local stackRect = (s.stackSide == "right") and rightRect or leftRect
    for _, w in ipairs(s.stack) do w:setFrame(stackRect) end
    s.left:setFrame(leftRect)
    s.right:setFrame(rightRect)
    s.left:raise(); s.right:raise()
  end

end

-- Remember this session as the hint the next press resolves against.
local function commitSplit(scr, s)
  split.screenId  = scr:id()
  split.leftId    = s.left  and s.left:id()
  split.rightId   = s.right and s.right:id()
  split.ratio     = s.ratio
  split.stackSide = s.stackSide or "left"
  split.stack     = {}
  for _, w in ipairs(s.stack) do split.stack[#split.stack + 1] = w:id() end
end

-- The usual pairing: lay it out, then remember it.
local function applySplit(scr, s)
  renderSplit(scr, s)
  commitSplit(scr, s)
end

-- A brief read-out of the split whenever it changes. The stack is invisible by
-- design (it lives behind the left pane), so without this you cannot tell what
-- rotating just did, or where you are in the ring.
local HUD = {
  w = 960, h = 94, top = 56, secs = 1.6,
  face  = "Helvetica Neue", size = 21, sub = 18,
  ink   = { white = 1, alpha = 1 },
  live  = { red = 1.00, green = 0.82, blue = 0.42, alpha = 1 },
  panel = { red = 0.04, green = 0.05, blue = 0.07, alpha = 0.94 },
}
local hudCanvas, hudTimer = nil, nil

local function winLabel(w, withTitle)
  if not w then return "(empty)" end
  local app  = w:application()
  local name = (app and app:name()) or "?"
  if not withTitle then return name end
  local t = w:title() or ""
  if #t > 0 and t ~= name then
    if #t > 26 then t = t:sub(1, 25) .. "…" end
    return name .. "  " .. t
  end
  return name
end

local function showSplitHud(scr, s, side)
  if hudTimer  then hudTimer:stop();     hudTimer  = nil end
  if hudCanvas then hudCanvas:delete();  hudCanvas = nil end

  local sf = scr:frame()
  local c = hs.canvas.new({ x = sf.x + (sf.w - HUD.w) / 2, y = sf.y + HUD.top,
                            w = HUD.w, h = HUD.h })
  c[#c + 1] = { type = "rectangle", action = "fill", fillColor = HUD.panel,
                roundedRectRadii = { xRadius = 14, yRadius = 14 } }

  local function seg(str, color, size, x, w, y)
    c[#c + 1] = { type = "text", text = str, textFont = HUD.face, textSize = size,
                  textColor = color, textAlignment = "center",
                  frame = { x = x, y = y, w = w, h = size + 12 } }
  end

  local half = HUD.w / 2 - 24
  seg(winLabel(s.left, true),  side == "left"  and HUD.live or HUD.ink, HUD.size, 12, half, 15)
  seg("│", HUD.ink, HUD.size, HUD.w / 2 - 12, 24, 15)
  seg(winLabel(s.right, true), side == "right" and HUD.live or HUD.ink, HUD.size,
      HUD.w / 2 + 12, half, 15)

  local names = {}
  for _, w in ipairs(s.stack) do names[#names + 1] = winLabel(w) end
  seg(#names > 0 and ("behind:   " .. table.concat(names, "   ·   ")) or "nothing behind",
      HUD.ink, HUD.sub, 12, HUD.w - 24, 52)

  c:level(hs.canvas.windowLevels.overlay)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  c:show(0.08)
  hudCanvas = c
  hudTimer = hs.timer.doAfter(HUD.secs, function()
    if hudCanvas then hudCanvas:delete(); hudCanvas = nil end
    hudTimer = nil
  end)
end

-- Which pane the keyboard is in. Defaults to left, so the split keys are never dead.
local function focusedSide(s)
  local f = hs.window.focusedWindow()
  if f and s.right and f:id() == s.right:id() then return "right" end
  return "left"
end

local function layoutSplit()
  local scr = focusedScreen()
  local s = splitSession(scr)
  if not s then return end
  applySplit(scr, s)
  -- Leave the keyboard somewhere predictable, but don't yank it out of a pane
  -- you are already working in.
  local f = hs.window.focusedWindow()
  local inPane = f and ((s.left and f:id() == s.left:id())
                     or (s.right and f:id() == s.right:id()))
  if not inPane and s.left then s.left:focus() end
  showSplitHud(scr, s, focusedSide(s))
end

-- Rotate the focused pane through the stack. The outgoing window takes the
-- incoming one's place in the ring, so with N windows stacked, N+1 presses of
-- alt-cmd-] land you exactly where you started and alt-cmd-[ is its inverse.
local function cycleSplit(dir)
  return function()
    local scr = focusedScreen()
    local s = splitSession(scr)
    if not s or #s.stack == 0 then return end
    local side = focusedSide(s)
    local cur  = s[side]
    if not cur then return end

    local incoming
    if dir > 0 then
      incoming = table.remove(s.stack, 1)
      table.insert(s.stack, cur)
    else
      incoming = table.remove(s.stack)
      table.insert(s.stack, 1, cur)
    end

    s[side]     = incoming
    s.stackSide = side          -- the pile follows the pane you are cycling
    applySplit(scr, s)
    incoming:focus()
    showSplitHud(scr, s, side)
  end
end

-- Trade places. Only the two panes move; the stack stays where it is.
local function swapSplit()
  local scr = focusedScreen()
  local s = splitSession(scr)
  if not s or not (s.left and s.right) then return end
  s.left, s.right = s.right, s.left
  applySplit(scr, s)
  showSplitHud(scr, s, focusedSide(s))
end

-- Move the divider one detent, in whichever direction makes the FOCUSED pane
-- bigger (grow) or smaller. Relative to where the keyboard is, like the cycle
-- keys, so there is one rule rather than a left key and a right key.
local function nudgeSplit(grow)
  return function()
    local scr = focusedScreen()
    local s = splitSession(scr)
    if not s or not (s.left and s.right) then return end

    local detents = splitDetents(scr)
    local cur, at = s.ratio or 0.5, 1
    for i, r in ipairs(detents) do
      if math.abs(r - cur) < math.abs(detents[at] - cur) then at = i end
    end

    -- growing the right pane means shrinking the left share, and the reverse
    local step = ((focusedSide(s) == "left") == grow) and 1 or -1
    s.ratio = detents[math.max(1, math.min(#detents, at + step))]
    applySplit(scr, s)
    showSplitHud(scr, s, focusedSide(s))
  end
end

-- Spatial focus, which cmd-tab cannot do: cmd-tab is app-ordered, this is
-- left/right. Establishes the split if there isn't one, so it is never a dead key.
local function focusSplitSide(side)
  return function()
    local scr = focusedScreen()
    local s = splitSession(scr)
    if not s then return end
    applySplit(scr, s)
    if s[side] then s[side]:focus() end
    showSplitHud(scr, s, side)
  end
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
-- One table drives both the bindings and the on-screen cheatsheet (alt-cmd-/),
-- so the two can never drift apart.

local function focusApp(bundleID)
  return function() hs.application.launchOrFocusByBundleID(bundleID) end
end

-- Diagnostic: dump Zoom + Teams window titles (use mid meeting/share to tune matchers).
local ZOOM_LOG = os.getenv("HOME") .. "/.hammerspoon/zoom-titles.log"
local function dumpMeetingTitles()
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
end

-- Diagnostic: focused screen name, resolution, detected profile.
local function showScreenInfo()
  local s = focusedScreen()
  local f = s:frame()
  hs.alert.show(string.format("Screen: %s\n%dx%d  (profile: %s)",
    s:name() or "?", math.floor(f.w), math.floor(f.h), screenProfile(s)), 6)
end

local toggleCheatsheet   -- defined below; it renders from BINDINGS

local BINDINGS = {
  { "Layouts", {
    { "f", "focus: one app centered, cmd-tab between all", layoutFocus },
    { "g", "zen: the same, in a narrow column",            layoutZen },
    { "w", "split: two panes, everything else stacked",    layoutSplit },
    { "e", "grid: every window, balanced",                 layoutGrid },
    { "c", "meeting shape: meeting + Slack left, you right", layoutMeeting },
    { "r", "control room: same shape, wider right pane",   layoutControlRoom },
    { "m", "meeting (also fires automatically on a call)", layoutMeeting },
  }},
  { "Split", {
    { "]", "rotate the focused pane forward through the stack", cycleSplit(1) },
    { "[", "rotate it back",                                    cycleSplit(-1) },
    { "x", "swap the two panes",                                swapSplit },
    { "=", "grow the focused pane one detent",                  nudgeSplit(true) },
    { "-", "shrink it one detent",                              nudgeSplit(false) },
    { "h", "focus the left pane",                               focusSplitSide("left") },
    { "l", "focus the right pane",                              focusSplitSide("right") },
  }},
  { "Jump to app", {
    { "s", "Slack",   focusApp(BUNDLE.slack) },
    { "a", "Arc",     focusApp(BUNDLE.arc) },
    { "v", "VS Code", focusApp(BUNDLE.vscode) },
    { "z", "Zoom",    focusApp(BUNDLE.zoom) },
  }},
  { "Diagnostics", {
    { "9", "screen name, size, detected profile", showScreenInfo },
    { "0", "dump Zoom / Teams window titles",     dumpMeetingTitles },
    { "/", "this cheatsheet",                     function() toggleCheatsheet() end },
  }},
}

-- Every binding goes through here, so a hotkey can never fail silently again.
-- An unguarded callback that errors just stops, which is how `focusedSide` sat
-- broken for nine days: the split applied, the HUD died, nothing said so.
local function safe(label, fn)
  return function()
    local ok, err = pcall(fn)
    if not ok then
      hs.alert.show("mesa: " .. label .. "\n" .. tostring(err), 4)
      print("mesa ERROR in " .. label .. ": " .. tostring(err))
    end
  end
end

for _, group in ipairs(BINDINGS) do
  for _, b in ipairs(group[2]) do
    hs.hotkey.bind({ "alt", "cmd" }, b[1], safe(b[2], b[3]))
  end
end

-- Which way the Rainy 75 is reaching this Mac. Wobkey ships a different USB
-- product ID per connection mode (the reason there is a VIA JSON per mode), so
-- the HID tree answers it outright: 0x5055 wired, 0x5088 the 2.4GHz dongle.
-- ~0.2s, so it runs when the sheet opens rather than on a timer.
local function rainyConnection()
  local ok, out = pcall(hs.execute,
    [==[/usr/sbin/ioreg -c IOHIDDevice -r -d 1 | /usr/bin/grep -E '"(VendorID|ProductID)"']==])
  if not ok or type(out) ~= "string" then return "could not read" end
  if out:find("20565", 1, true) then return "wired (USB-C)" end      -- 0x5055
  if out:find("20616", 1, true) then return "2.4GHz dongle" end      -- 0x5088
  if out:find("12815", 1, true) then return "Bluetooth" end          -- 0x320F, no USB pid
  return "not connected"
end

-- Reference-only sections: nothing is bound, they just share the sheet.
-- A description may be a function, evaluated each time the sheet opens, for
-- rows that report live state rather than a fixed shortcut.
-- Wobkey Rainy 75 Pro in macOS mode (Fn+M). The keycaps are swapped, so the cap
-- marked Win sends Command and the cap marked Alt sends Option.
local REFERENCE = {
  { "Rainy 75", {
    { "connection", rainyConnection },
    { "Fn + M",     "hold 3s: switch macOS / Windows layout" },
    { "Fn + Tab",   "cycle wired / BT 1-3 / 2.4GHz dongle" },
    { "Fn + F1..3", "hold 3s: re-pair that Bluetooth slot" },
    { "Fn + Space", "battery level, each number key is 10%" },
    { "Fn + L",     "long battery mode, trades speed for runtime" },
    { "Fn + H",     "ultra-low latency, for gaming, leave it off" },
    { "Esc",        "hold 3s: factory reset, wipes the keymap" },
  }},
  { "Lighting", {
    { "Fn + \\",    "cycle the 18 lighting modes" },
    { "Fn + Bksp",  "backlight on / off" },
    { "Fn + Enter", "switch static colour" },
    { "Fn + up/dn", "brightness" },
    { "Fn + lt/rt", "effect speed" },
  }},
  { "Worth knowing", {
    { "power",    "switch hides under the Caps Lock keycap" },
    { "charging", "5V 1-2A only, never a fast charger" },
    { "sleep",    "1 min idle, any key wakes it" },
    { "dongle",   "within 15cm, away from USB 3 ports" },
    { "VIA",      "usevia.app, Chromium only, not Safari" },
    { "firmware", "updater is a Windows .exe, leave it alone" },
    { "dead keys","turn Fn + H off before anything else" },
  }},
}

-- ---------------------------------------------------------------------------
-- Cheatsheet (alt-cmd-/)
-- ---------------------------------------------------------------------------
-- A canvas overlay rather than an hs.alert, so the type can be big. Two balanced
-- columns: the bindings first, then the Rainy 75 reference. Escape, a click, or
-- alt-cmd-/ again dismisses it.

local SHEET = {
  pad      = 40,
  gutter   = 44,
  colW     = 570,  -- one column: key column plus its descriptions
  rowH     = 30,   -- one binding
  headH    = 42,   -- a section header, spacing included
  titleH   = 60,
  keyColW  = 130,
  titleSize = 27,
  headSize  = 17,
  rowSize   = 19,
  face      = "Helvetica Neue",
  mono      = "Menlo",
  ink       = { white = 1, alpha = 1 },
  key       = { red = 1.00, green = 0.82, blue = 0.42, alpha = 1 },
  head      = { red = 0.52, green = 0.78, blue = 1.00, alpha = 1 },
  panel     = { red = 0.04, green = 0.05, blue = 0.07, alpha = 0.95 },
  edge      = { white = 1, alpha = 0.20 },
}
SHEET.w = SHEET.pad * 2 + SHEET.colW * 2 + SHEET.gutter

local cheatsheet = nil
local sheetModal = hs.hotkey.modal.new()
sheetModal:bind({}, "escape", function() toggleCheatsheet() end)

-- Every section from both tables, measured so the columns can be balanced.
local function sheetSections()
  local out = {}
  local function add(groups, keyFor)
    for _, g in ipairs(groups) do
      local rows = {}
      for _, b in ipairs(g[2]) do
        local desc = b[2]
        if type(desc) == "function" then desc = desc() end
        rows[#rows + 1] = { key = keyFor(b), desc = desc }
      end
      out[#out + 1] = { head = g[1], rows = rows,
                        h = SHEET.headH + #rows * SHEET.rowH }
    end
  end
  add(BINDINGS,  function(b) return "⌥⌘" .. b[1]:upper() end)
  add(REFERENCE, function(b) return b[1] end)
  return out
end

-- Fill the left column until it passes half the total height, the rest goes
-- right. Sections stay whole and in order, so each column reads top to bottom.
local function sheetColumns()
  local secs, total = sheetSections(), 0
  for _, s in ipairs(secs) do total = total + s.h end

  local left, right, run = {}, {}, 0
  for _, s in ipairs(secs) do
    if run < total / 2 then
      left[#left + 1] = s; run = run + s.h
    else
      right[#right + 1] = s
    end
  end
  return left, right, math.max(run, total - run)
end

toggleCheatsheet = function()
  if cheatsheet then
    cheatsheet:delete(); cheatsheet = nil; sheetModal:exit()
    return
  end

  local left, right, colH = sheetColumns()
  local h = SHEET.pad * 2 + SHEET.titleH + colH

  local sf = focusedScreen():frame()
  -- Clamp to the top: on a laptop screen a tall sheet must not start above the
  -- menu bar, where its first rows would be cut off.
  local c = hs.canvas.new({ x = sf.x + (sf.w - SHEET.w) / 2,
                            y = math.max(sf.y, sf.y + (sf.h - h) / 2),
                            w = SHEET.w, h = h })

  local radii = { xRadius = 18, yRadius = 18 }
  c[#c + 1] = { type = "rectangle", action = "fill",   roundedRectRadii = radii,
                fillColor = SHEET.panel }
  c[#c + 1] = { type = "rectangle", action = "stroke", roundedRectRadii = radii,
                strokeColor = SHEET.edge, strokeWidth = 1 }

  local function text(str, x, y, w, size, color, font)
    c[#c + 1] = { type = "text", text = str, textFont = font or SHEET.face,
                  textSize = size, textColor = color,
                  frame = { x = x, y = y, w = w, h = size + 12 } }
  end

  local function column(secs, x, y)
    for _, s in ipairs(secs) do
      text(s.head:upper(), x, y + 14, SHEET.colW, SHEET.headSize, SHEET.head)
      y = y + SHEET.headH
      for _, r in ipairs(s.rows) do
        text(r.key, x, y, SHEET.keyColW, SHEET.rowSize, SHEET.key, SHEET.mono)
        text(r.desc, x + SHEET.keyColW, y, SHEET.colW - SHEET.keyColW,
             SHEET.rowSize, SHEET.ink)
        y = y + SHEET.rowH
      end
    end
  end

  local top = SHEET.pad
  text("mesa  ·  layouts & keyboard", SHEET.pad, top,
       SHEET.w - 2 * SHEET.pad, SHEET.titleSize, SHEET.ink)
  top = top + SHEET.titleH

  column(left,  SHEET.pad, top)
  column(right, SHEET.pad + SHEET.colW + SHEET.gutter, top)

  c:level(hs.canvas.windowLevels.overlay)
  c:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  c:canvasMouseEvents(true, false, false, false)
  c:mouseCallback(function() toggleCheatsheet() end)
  c:show(0.12)

  cheatsheet = c
  sheetModal:enter()
end

hs.alert.show("Window layouts loaded")
