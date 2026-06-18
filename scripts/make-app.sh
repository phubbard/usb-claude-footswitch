#!/usr/bin/env bash
# Build the executable with SwiftPM and assemble a proper .app bundle.
#
# Env overrides:
#   CONFIG=debug|release        (default: release)
#   CODE_SIGN_IDENTITY="..."    (default: a stable local identity via signing-setup.sh;
#                                set to a Developer ID to use your own)
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
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

# Signing identity, in priority order. Any real identity keeps macOS TCC grants
# (Accessibility, Input Monitoring) across rebuilds; ad-hoc does not.
#   1. CODE_SIGN_IDENTITY override
#   2. a "Developer ID Application" identity (stable, Gatekeeper-trusted, notarizable)
#   3. a stable local self-signed identity (scripts/signing-setup.sh)
#   4. ad-hoc fallback
KEYCHAIN_FLAG=()
SIGN_OPTS=()
DEV_ID="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')"
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    IDENTITY="$CODE_SIGN_IDENTITY"
    SIGN_OPTS=(--options runtime)
elif [ -n "$DEV_ID" ]; then
    IDENTITY="$DEV_ID"
    SIGN_OPTS=(--options runtime)   # hardened runtime → notarization-ready
elif OUT="$(bash scripts/signing-setup.sh)"; then
    eval "$OUT"
    IDENTITY="$SIGN_IDENTITY"
    KEYCHAIN_FLAG=(--keychain "$SIGN_KEYCHAIN")
else
    echo "⚠ Local signing setup failed; using ad-hoc (TCC grants won't survive rebuilds)."
    IDENTITY="-"
fi

echo "▸ Signing (identity: $IDENTITY)…"
# ${arr[@]+"${arr[@]}"} expands safely to nothing when the array is empty (bash 3.2 + set -u).
codesign --force --sign "$IDENTITY" \
    ${KEYCHAIN_FLAG[@]+"${KEYCHAIN_FLAG[@]}"} \
    ${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"} \
    --timestamp=none "$APP"

echo "✓ Built $APP"
echo
echo "Next:"
echo "  • Launch:        open \"$APP\""
echo "  • Install:       make install   (copies to /Applications)"
echo "  • Grant Input Monitoring + Accessibility when prompted, then relaunch."
