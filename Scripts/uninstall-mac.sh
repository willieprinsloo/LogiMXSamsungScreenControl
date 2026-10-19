#!/bin/bash
# Uninstall G9 Keyboard Switch: quit, remove the .app, and optionally wipe config.
# Note: SMAppService login items for a removed app may still appear in
# System Settings → General → Login Items until the user clicks the (-) there.
set -euo pipefail

APP_NAME="G9 Keyboard Switch"
BUNDLE_ID="solutions.metalogix.g9switch"
DST="/Applications/$APP_NAME.app"
SUPPORT="$HOME/Library/Application Support/G9KeyboardSwitch"

echo "==> Quitting running instance"
pkill -f "MacOS/G9KeyboardSwitch" 2>/dev/null || true
sleep 1

if [ -d "$DST" ]; then
  echo "==> Removing $DST"
  if ! rm -rf "$DST" 2>/dev/null; then
    sudo rm -rf "$DST"
  fi
else
  echo "==> Nothing installed at $DST"
fi

read -r -p "Also wipe config at $SUPPORT? [y/N] " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  rm -rf "$SUPPORT"
  echo "   config removed"
fi

echo ""
echo "✅ Uninstalled."
echo "   If a stale Login Item lingers, remove it in System Settings → General → Login Items."
