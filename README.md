# mesa

A small, calm macOS window-layout system built on [Hammerspoon](https://www.hammerspoon.org).
Floating-first: it manages nothing on its own, it just snaps windows into a handful
of deliberate arrangements when you ask, and rearranges automatically for meetings.

Think **one / two / many**, plus one three-pane working shape at two widths, and an
automatic meeting mode.
Everything is app-agnostic and reflows with the number of windows (Hyprland-ish),
and it adapts to whichever screen you're on (laptop / desk / ultrawide).

## Layouts

| Hotkey | Layout | What it does |
|--------|--------|--------------|
| `⌥⌘F` | **focus** | ONE app, centered; `⌘Tab` between all windows |
| `⌥⌘G` | **zen** | the same one-window paradigm, but a NARROW centered column (~1600px on the ultrawide vs ~2100px for focus). Most of the screen goes back to wallpaper |
| `⌥⌘W` | **split** | the front TWO apps side by side; everything else folds behind them |
| `⌥⌘C` | **meeting shape** | three panes: the live meeting (or Zoom's calendar) top-left, Slack below it, the FOCUSED app big on the right; others fold behind. Focus a window and press again to cycle it into the big slot |
| `⌥⌘R` | **control room** | the SAME three panes, right pane widened for reading (email, docs). Only the divider moves — no pane changes place, so it's a shift of proportions, not a new layout |
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

- **Look**: `TILE_PAD`, `TILE_GAP` (split / grid margins).
- **Focus frame**: `NORMAL_PAD_TOP/SIDE/BOTTOM`, `LAPTOP_PAD`, `NOC_CENTER_PAD`.
- **Zen column**: `ZEN` — a fixed column *width* and vertical pad per display profile
  (`laptop` / `desk` / `noc`). A width, not a margin, so it stays deliberately small as
  the display gets wider. Capped at the focus width, so zen is never the bigger of the two.
- **Three panes**: `MEETING_FRACTION` and `CONTROL_FRACTION` (right-pane width share for
  `⌥⌘C` and `⌥⌘R`), `TOP_LEFT_SHARE` (what the top-left pane asks for), `GAP`.
  There is no per-app minimum height to maintain: the top pane is placed, then measured
  (Zoom refuses to go under ~650px), and the bottom pane takes the real remainder.
- **Apps**: `BUNDLE = { ... }` maps roles to app bundle IDs. Change these for your own apps
  (find a bundle ID with `mdls -name kMDItemCFBundleIdentifier /Applications/Name.app`).

## Meeting detection notes

- **Zoom** is matched by title patterns (including the screen-share toolbars, so a
  share doesn't read as "meeting ended").
- **Teams** names a meeting window `<subject> | Microsoft Teams`, with no keyword, so
  it's matched as "any Teams window except the known idle tabs (Chat, Calendar, …)".
- If a meeting ever fails to auto-arrange, press `⌥⌘0` mid-call to dump the real
  window titles and tune the patterns in `MEETING_APPS`.

## Requirements

macOS, Hammerspoon, and Accessibility permission. That's it.
