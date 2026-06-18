#!/usr/bin/env bash
# Build the executable with SwiftPM and assemble a proper .app bundle.
#
# Env overrides:
#   CONFIG=debug|release        (default: release)
#   CODE_SIGN_IDENTITY="..."    (default: "-" ad-hoc; use a Developer ID for stable TCC grants)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
APP_NAME="Claude Footswitch"
EXECUTABLE="ClaudeFootswitch"
APP="build/${APP_NAME}.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$EXECUTABLE"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "▸ Icon missing — building it…"
    bash scripts/make-icon.sh
fi

echo "▸ Assembling $APP …"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signing (identity: $IDENTITY)…"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP"

echo "✓ Built $APP"
echo
echo "Next:"
echo "  • Launch:        open \"$APP\""
echo "  • Install:       make install   (copies to /Applications)"
echo "  • Grant Input Monitoring + Accessibility when prompted, then relaunch."
