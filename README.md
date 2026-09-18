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
| `⌥⌘W` | **split** | two panes side by side; everything else folds into a stack behind the left one |
| `⌥⌘C` | **meeting shape** | three panes: the live meeting (or Zoom's calendar) top-left, Slack below it, the FOCUSED app big on the right; others fold behind. Focus a window and press again to cycle it into the big slot |
| `⌥⌘R` | **control room** | the SAME three panes, right pane widened for reading (email, docs). Only the divider moves — no pane changes place, so it's a shift of proportions, not a new layout |
| `⌥⌘E` | **grid** | ALL apps in a balanced grid (2 → side by side, 3 → 2+1, 4 → 2×2) |
| `⌥⌘M` | **meeting** | auto-fires on a Zoom/Teams meeting or a Slack huddle; desk = 3-pane (meeting video top-left near the camera, chat below, browser right), laptop = single window. Reverts when the call ends |

### Working inside a split

Split is the one layout that remembers something between presses, because cycling needs
something to cycle. Whatever isn't in the two panes is a **stack** sitting behind the left
pane, and these keys move things through it:

| Hotkey | What it does |
|--------|--------------|
| `⌥⌘]` | rotate the **focused** pane forward through the stack |
| `⌥⌘[` | rotate it back (the exact inverse) |
| `⌥⌘X` | swap the two panes; nothing resizes |
| `⌥⌘=` / `⌥⌘-` | grow / shrink the focused pane by one detent |
| `⌥⌘H` / `⌥⌘L` | put the keyboard in the left / right pane |

Every one of these keys flashes a **read-out** at the top of the screen for a moment:
the two panes (the one you're acting on in amber) and, below, what's in the stack and in
what order. The stack is invisible by design, since it sits behind the left pane, so
without that you can't see what a rotate just did.

The divider moves in **detents** (0.38 / 0.5 / 0.62 of the usable width) rather than as a
free drag, so it stays a shift of proportions like control room is to meeting. A detent
that would leave either pane under `MIN_PANE_W` isn't offered, which on the laptop leaves
only the even split. `⌥⌘=` always grows *the pane you're in*, so there's one rule rather
than a left key and a right key.

It's a rotation, not a shuffle: the window leaving a pane takes the incoming one's place in
the ring, so with N windows stacked, N+1 presses of `⌥⌘]` land you back exactly where you
started. `⌥⌘H`/`⌥⌘L` is the spatial move `⌘Tab` can't do (`⌘Tab` is app-ordered, this is
left/right), and all four keys establish the split first if you aren't in one, so none of
them is ever a dead key.

The remembered session is a **hint, not the truth**. Every press re-resolves it against the
live windows: anything closed, moved to another screen or no longer tileable drops out and
is topped up from the front of the window order. A stale session decays back into the plain
"front two, rest behind" split rather than getting stuck.

Jump straight to an app: `⌥⌘S` Slack · `⌥⌘A` Arc · `⌥⌘V` VS Code · `⌥⌘Z` Zoom.
Diagnostics: `⌥⌘9` screen name/size/profile · `⌥⌘0` dump live Zoom/Teams/Slack window titles.
**Cheatsheet: `⌥⌘/`** puts every binding on screen in large type; escape, a click, or `⌥⌘/`
again closes it. It renders from the same `BINDINGS` table that does the binding, so it
can't go stale.

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
- **Split box**: `SPLIT_BOX` — on the ultrawide, split stops full-bleeding and becomes two
  columns of a fixed `paneW` in a centered box (same "a width, not a margin" idea as zen and
  control room). `paneW` is set to `ZEN.noc.w`, so a split on the ultrawide is literally two
  zen columns side by side. `nil` = full bleed, which is what laptop and desk still do.
- **Divider**: `SPLIT_RATIOS` — the detents `⌥⌘=`/`⌥⌘-` step through, as the left pane's
  share of the usable width. `MIN_PANE_W` drops any detent that would leave a pane too
  thin to work in.
- **Cheatsheet / read-out**: `SHEET` and `HUD` — panel sizes, type sizes and colours.
- **Apps**: `BUNDLE = { ... }` maps roles to app bundle IDs. Change these for your own apps
  (find a bundle ID with `mdls -name kMDItemCFBundleIdentifier /Applications/Name.app`).

## Meeting detection notes

- **Zoom** is matched by title patterns (including the screen-share toolbars, so a
  share doesn't read as "meeting ended").
- **Teams** names a meeting window `<subject> | Microsoft Teams`, with no keyword, so
  it's matched as "any Teams window except the known idle tabs (Chat, Calendar, …)".
- **Slack huddles** can't be matched that way at all. A huddle opens a second Slack
  window that is identical to the first in every respect an app can see — same subrole,
  same buttons, same (empty) accessibility tree. The only difference is that Slack marks
  the main window `… - Slack [Main]` once a second window exists, so the test is
  relational: a standard Slack window that isn't the marked one, *and only while the
  marker is present*. That second condition is what keeps ordinary single-window Slack
  from reading as a call, whichever way Slack handles the marker when alone. The huddle
  window takes the top-left slot and Slack's main window stays in the pane below it.
  A popped-out thread or channel window would also read as a huddle; exclude it by title
  in `slackHuddleWindow` if that ever bites.
- If a meeting ever fails to auto-arrange, press `⌥⌘0` mid-call to dump the real
  window titles and tune the patterns in `MEETING_APPS`.

## Requirements

macOS, Hammerspoon, and Accessibility permission. That's it.
