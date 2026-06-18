#!/usr/bin/env bash
# Notarize and staple a .app or .dmg with notarytool (App Store Connect API key).
#
# Needs:
#   AC_API_KEY_ID     the key's Key ID
#   AC_API_ISSUER_ID  the issuer UUID
#   AC_API_KEY        path to the .p8 key file   (or…)
#   AC_API_KEY_P8     the .p8 contents (used in CI from a secret)
#
# No-op (with a warning) when those aren't set, so local builds still succeed.
set -euo pipefail

TARGET="${1:?usage: notarize.sh <path-to-.app-or-.dmg>}"

if [ -z "${AC_API_KEY_ID:-}" ] || [ -z "${AC_API_ISSUER_ID:-}" ] \
   || { [ -z "${AC_API_KEY:-}" ] && [ -z "${AC_API_KEY_P8:-}" ]; }; then
    echo "⚠ Notarization skipped for $TARGET (App Store Connect API key not configured)."
    exit 0
fi

KEYFILE="${AC_API_KEY:-}"
CLEANUP=""
if [ -z "$KEYFILE" ]; then
    KEYFILE="$(mktemp).p8"
    printf '%s' "$AC_API_KEY_P8" > "$KEYFILE"
    CLEANUP="$KEYFILE"
fi
trap '[ -n "$CLEANUP" ] && rm -f "$CLEANUP"' EXIT

submit() {
    xcrun notarytool submit "$1" \
        --key "$KEYFILE" --key-id "$AC_API_KEY_ID" --issuer "$AC_API_ISSUER_ID" \
        --wait
}

echo "▸ Notarizing $TARGET…"
case "$TARGET" in
    *.app)
        # notarytool can't take a bare .app — zip it, submit, then staple the app itself.
        ZIPDIR="$(mktemp -d)"
        ditto -c -k --keepParent "$TARGET" "$ZIPDIR/app.zip"
        submit "$ZIPDIR/app.zip"
        rm -rf "$ZIPDIR"
        ;;
    *)
        submit "$TARGET"
        ;;
esac

echo "▸ Stapling $TARGET…"
xcrun stapler staple "$TARGET"
echo "✓ Notarized & stapled $TARGET"
