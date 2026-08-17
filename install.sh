#!/usr/bin/env bash
# mesa — symlink the Hammerspoon window-layout config into place and check deps.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO/init.lua"
HS_DIR="$HOME/.hammerspoon"
DEST="$HS_DIR/init.lua"

echo "mesa install"
echo "  repo: $REPO"

# 1. Hammerspoon present?
if [ ! -d "/Applications/Hammerspoon.app" ]; then
  if command -v brew >/dev/null 2>&1; then
    echo "  Hammerspoon not found — installing via Homebrew..."
    brew install --cask hammerspoon
  else
    echo "  !! Hammerspoon not installed and Homebrew not found."
    echo "     Get it from https://www.hammerspoon.org, then re-run this script."
    exit 1
  fi
else
  echo "  Hammerspoon: present"
fi

# 2. Symlink the config (back up any existing real file first)
mkdir -p "$HS_DIR"
if [ -L "$DEST" ]; then
  rm "$DEST"
elif [ -e "$DEST" ]; then
  bak="$DEST.backup.$(date +%Y%m%d-%H%M%S)"
  echo "  backing up existing init.lua -> $bak"
  mv "$DEST" "$bak"
fi
ln -s "$SRC" "$DEST"
echo "  linked: $DEST -> $SRC"

# 3. Launch (loads the config)
open -a Hammerspoon 2>/dev/null || true

cat <<'NEXT'

Almost there — two manual steps:
  1. Grant Accessibility permission:
     System Settings > Privacy & Security > Accessibility > enable Hammerspoon
  2. Hammerspoon menu-bar icon > Reload Config
     (you should see a "Window layouts loaded" alert)

Hotkeys (all alt-cmd):
  f focus (one) · w split (two) · c control-room · e grid (many) · m meeting
  s/a/v/z jump to Slack/Arc/VS Code/Zoom · 9 screen info · 0 meeting-title diagnostic

Tweak the app bundle IDs (BUNDLE = {...}) at the top of init.lua for your own apps.
NEXT
