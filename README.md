# mesa

A small, calm macOS window-layout system built on [Hammerspoon](https://www.hammerspoon.org).
Floating-first: it manages nothing on its own, it just snaps windows into a handful
of deliberate arrangements when you ask, and rearranges automatically for meetings.

Think **one / two / many**, plus a workstation dashboard and an automatic meeting mode.
Everything is app-agnostic and reflows with the number of windows (Hyprland-ish),
and it adapts to whichever screen you're on (laptop / desk / ultrawide).

## Layouts

| Hotkey | Layout | What it does |
|--------|--------|--------------|
| `⌥⌘F` | **focus** | ONE app, centered; `⌘Tab` between all windows |
| `⌥⌘W` | **split** | the front TWO apps side by side; everything else folds behind them |
| `⌥⌘C` | **control room** | the FOCUSED app big on the right; next two on the left (bottom taller, top smaller); others behind. Focus a window and press again to cycle it into the big slot |
| `⌥⌘E` | **grid** | ALL apps in a balanced grid (2 → side by side, 3 → 2+1, 4 → 2×2) |
| `⌥⌘M` | **meeting** | auto-fires on a Zoom/Teams meeting; desk = 3-pane (meeting video top-left near the camera, chat below, browser right), laptop = single window. Reverts when the call ends |

Jump straight to an app: `⌥⌘S` Slack · `⌥⌘A` Arc · `⌥⌘V` VS Code · `⌥⌘Z` Zoom.
Diagnostics: `⌥⌘9` screen name/size/profile · `⌥⌘0` dump live Zoom/Teams window titles.

## Install

```bash
git clone <this-repo> ~/CharliesCode/mesa
cd ~/CharliesCode/mesa
./install.sh
```

`install.sh` installs Hammerspoon (via Homebrew if needed), backs up any existing
`~/.hammerspoon/init.lua`, and symlinks this repo's `init.lua` into place. Then:

1. **Grant Accessibility**: System Settings → Privacy & Security → Accessibility → enable Hammerspoon.
2. Hammerspoon menu-bar icon → **Reload Config**.

Because it's a symlink, editing `init.lua` in this repo updates the live config
(just reload Hammerspoon). Handy: the `hs` CLI is auto-installed, so you can
introspect live with `hs -c '...'`.

## Screen profiles

Layouts adapt by display, detected from the screen name/width:

- **laptop** (built-in retina, any resolution): near-maximise / single-window.
- **desk** (a normal external, default): centered boxes.
- **noc** (curved ultrawide ≥ 3200px wide): wider centered apps.

## Tuning

Everything is named constants at the top of `init.lua`:

- **Look**: `TILE_PAD`, `TILE_GAP` (split / grid / dashboard margins).
- **Control room**: `DASH_MAIN_FRACTION` (big pane width), `DASH_BOTTOM_FRACTION` (bottom-left height).
- **Focus frame**: `NORMAL_PAD_TOP/SIDE/BOTTOM`, `LAPTOP_PAD`, `NOC_CENTER_PAD`.
- **Meeting**: `ARC_FRACTION`, `SLACK_FRACTION`, `MEETING_MIN_H` (meeting-window min height, ~680 covers Zoom and Teams), `GAP`.
- **Apps**: `BUNDLE = { ... }` maps roles to app bundle IDs. Change these for your own apps
  (find a bundle ID with `mdls -name kMDItemCFBundleIdentifier /Applications/Name.app`).

## Meeting detection notes

- **Zoom** is matched by title patterns (including the screen-share toolbars, so a
  share doesn't read as "meeting ended").
- **Teams** names a meeting window `<subject> | Microsoft Teams`, with no keyword, so
  it's matched as "any Teams window except the known idle tabs (Chat, Calendar, …)".
- If a meeting ever fails to auto-arrange, press `⌥⌘0` mid-call to dump the real
  window titles and tune the patterns in `MEETING_APPS`.

## Useful things

Beyond the window layouts, this repo doubles as a table (a *mesa*) for things worth
remembering: see [`useful/`](useful/). First list: [good software](useful/good-software.md).

## Requirements

macOS, Hammerspoon, and Accessibility permission. That's it.
