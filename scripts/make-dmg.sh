#!/usr/bin/env bash
# Package the built .app into a compressed, optionally-signed DMG with an /Applications
# drop target.
#
# Env:
#   VERSION=1.2.3            (default: the app's CFBundleShortVersionString)
#   CODE_SIGN_IDENTITY=...   (default: Developer ID if present)
#   SECURE_TIMESTAMP=1       use a secure timestamp on the DMG signature
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Claude Footswitch"
APP="build/${APP_NAME}.app"
[ -d "$APP" ] || { echo "✕ $APP not found — run scripts/make-app.sh first"; exit 1; }

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")}"
DMG="build/ClaudeFootswitch-${VERSION}.dmg"

echo "▸ Staging…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "▸ Creating ${DMG}…"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')"
IDENTITY="${CODE_SIGN_IDENTITY:-$DEV_ID}"
if [ -n "$IDENTITY" ] && [ "$IDENTITY" != "-" ]; then
    TS=(--timestamp=none); [ "${SECURE_TIMESTAMP:-0}" = "1" ] && TS=(--timestamp)
    echo "▸ Signing DMG ($IDENTITY)…"
    codesign --force --sign "$IDENTITY" "${TS[@]}" "$DMG"
fi

echo "✓ $DMG"
