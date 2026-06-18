#!/usr/bin/env bash
# CI only: import a Developer ID certificate into a temporary keychain so codesign can find
# it (make-app.sh / make-dmg.sh auto-detect "Developer ID Application").
#
# Needs:
#   DEVELOPER_ID_P12_BASE64    base64 of the exported .p12 (cert + private key)
#   DEVELOPER_ID_P12_PASSWORD  the .p12 export password
#
# No-op (with a warning) when the cert isn't provided, so the release still builds (ad-hoc).
set -euo pipefail

if [ -z "${DEVELOPER_ID_P12_BASE64:-}" ]; then
    echo "⚠ DEVELOPER_ID_P12_BASE64 not set — build will be ad-hoc / unsigned."
    exit 0
fi

KEYCHAIN="${RUNNER_TEMP:-/tmp}/codesign.keychain-db"
KC_PASS="$(uuidgen)"
P12="${RUNNER_TEMP:-/tmp}/developer-id.p12"

echo "$DEVELOPER_ID_P12_BASE64" | base64 --decode > "$P12"

security create-keychain -p "$KC_PASS" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "${DEVELOPER_ID_P12_PASSWORD:-}" -A -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null
# Make our keychain searchable (keep the login keychain too).
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | sed -e 's/"//g')
rm -f "$P12"

echo "✓ Imported signing identity:"
security find-identity -v -p codesigning "$KEYCHAIN"
