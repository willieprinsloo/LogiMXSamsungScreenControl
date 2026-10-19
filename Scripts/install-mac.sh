#!/bin/bash
# Install "G9 Keyboard Switch.app" to /Applications and launch it. Launching
# triggers SMAppService.mainApp.register(), so the app comes up automatically
# on every reboot/login. Toggle "Launch at login" in the menu to disable.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="G9 Keyboard Switch"
BUNDLE_ID="solutions.metalogix.g9switch"
SRC="$ROOT/dist/$APP_NAME.app"
DST="/Applications/$APP_NAME.app"

if [ ! -d "$SRC" ]; then
  echo "==> No build found at $SRC — building first"
  ./Scripts/build-app.sh
fi

echo "==> Quitting any running instance"
pkill -f "MacOS/G9KeyboardSwitch" 2>/dev/null || true
sleep 1

if [ -d "$DST" ]; then
  echo "==> Removing previous installation at $DST"
  if ! rm -rf "$DST" 2>/dev/null; then
    echo "   (needs admin — authenticating)"
    sudo rm -rf "$DST"
  fi
fi

echo "==> Copying to $DST"
if ! cp -R "$SRC" "$DST" 2>/dev/null; then
  echo "   (needs admin — authenticating)"
  sudo cp -R "$SRC" "$DST"
fi

echo "==> Enabling launch-at-login in config"
CFG="$HOME/Library/Application Support/G9KeyboardSwitch/config.json"
mkdir -p "$(dirname "$CFG")"
if [ -f "$CFG" ]; then
  python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]
try:
    d = json.load(open(p))
except Exception:
    d = {}
d["launchAtLogin"] = True
json.dump(d, open(p, "w"), indent=2)
PY
fi
# If no config yet, the app writes defaults on first run — defaults already have launchAtLogin=true.

echo "==> Launching installed app (this registers the login item)"
open "$DST"

echo ""
echo "✅ Installed."
echo "    App:    $DST"
echo "    Login:  the app registers itself on first launch; toggle via the menu bar"
echo "    Logs:   /usr/bin/log show --predicate 'subsystem == \"${BUNDLE_ID}\"' --last 5m"
echo ""
echo "Look for the display icon in the top-right menu bar."
