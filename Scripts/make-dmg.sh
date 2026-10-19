#!/bin/bash
# Build a drag-to-install DMG: contains "G9 Keyboard Switch.app" and an
# Applications symlink, so the user drops the app on Applications and
# launches it. Launching registers the login item for auto-start.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="G9 Keyboard Switch"
VOL_NAME="G9 Keyboard Switch"
SRC="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/G9KeyboardSwitch.dmg"
STAGE="$ROOT/dist/.dmg-stage"

if [ ! -d "$SRC" ]; then
  echo "==> No build found at $SRC — building first"
  ./Scripts/build-app.sh
fi

echo "==> Staging DMG contents"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$SRC" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"

echo ""
echo "✅ $DMG"
ls -lh "$DMG"
echo ""
echo "To install: open the DMG and drag the app onto Applications, then launch it."
