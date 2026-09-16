#!/bin/bash
# Build "G9 Keyboard Switch.app" — a menu-bar-only (LSUIElement) app bundle with
# the bundled m1ddc helper, ad-hoc code-signed for local use.
#
# Real distribution requires a Developer ID certificate + notarization; ad-hoc
# signing is for running on this machine only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="G9 Keyboard Switch"
BUNDLE_ID="solutions.metalogix.g9switch"
EXE_NAME="G9KeyboardSwitch"
BUILD_DIR="$ROOT/.build/release"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

echo "==> swift build -c release"
swift build -c release

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/$EXE_NAME" "$APP/Contents/MacOS/$EXE_NAME"

# Bundle m1ddc (Bundle.main.url(forResource:"m1ddc") resolves here).
cp "$ROOT/Sources/G9KeyboardSwitch/Resources/m1ddc" "$APP/Contents/Resources/m1ddc"
cp "$ROOT/Sources/G9KeyboardSwitch/Resources/m1ddc-LICENSE" "$APP/Contents/Resources/m1ddc-LICENSE"
chmod +x "$APP/Contents/Resources/m1ddc"

# Also copy the SwiftPM resource bundle so Bundle.module works as a fallback.
if [ -d "$BUILD_DIR/${EXE_NAME}_${EXE_NAME}.bundle" ]; then
  cp -R "$BUILD_DIR/${EXE_NAME}_${EXE_NAME}.bundle" "$APP/Contents/Resources/"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXE_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Bundles m1ddc (MIT). See m1ddc-LICENSE.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"

echo "==> Done: $APP"
