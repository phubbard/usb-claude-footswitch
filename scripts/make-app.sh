#!/usr/bin/env bash
# Build the executable with SwiftPM and assemble a signed .app bundle.
#
# Env overrides:
#   CONFIG=debug|release       (default: release)
#   UNIVERSAL=1                build a universal arm64+x86_64 binary
#   VERSION=1.2.3              stamp this version into the bundle's Info.plist
#   SECURE_TIMESTAMP=1         use a secure timestamp (required for notarization)
#   CODE_SIGN_IDENTITY="..."   force a signing identity. Otherwise: a Developer ID if one
#                              is present, else a stable local self-signed identity, else
#                              ad-hoc. Any real identity keeps TCC grants across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP_NAME="Claude Footswitch"
EXECUTABLE="ClaudeFootswitch"
APP="build/${APP_NAME}.app"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Building ($CONFIG${UNIVERSAL:+, universal})…"
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/$EXECUTABLE"

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

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
    echo "▸ Stamped version $VERSION"
fi

# Resolve a signing identity.
KEYCHAIN_FLAG=()
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')"
if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
    IDENTITY="$CODE_SIGN_IDENTITY"
elif [ -n "$DEV_ID" ]; then
    IDENTITY="$DEV_ID"
elif OUT="$(bash scripts/signing-setup.sh)"; then
    eval "$OUT"
    IDENTITY="$SIGN_IDENTITY"
    KEYCHAIN_FLAG=(--keychain "$SIGN_KEYCHAIN")
else
    echo "⚠ Local signing setup failed; using ad-hoc (TCC grants won't survive rebuilds)."
    IDENTITY="-"
fi

SIGN_OPTS=()
TS=(--timestamp=none)
if [ "$IDENTITY" != "-" ]; then
    SIGN_OPTS=(--options runtime)   # hardened runtime → notarization-ready
    [ "${SECURE_TIMESTAMP:-0}" = "1" ] && TS=(--timestamp)
fi

echo "▸ Signing (identity: $IDENTITY)…"
codesign --force --sign "$IDENTITY" \
    ${KEYCHAIN_FLAG[@]+"${KEYCHAIN_FLAG[@]}"} \
    ${SIGN_OPTS[@]+"${SIGN_OPTS[@]}"} \
    "${TS[@]}" "$APP"

codesign --verify --strict "$APP"
echo "✓ Built & signed $APP"
echo
echo "Next:  open \"$APP\"   •   make dmg   •   make install"
