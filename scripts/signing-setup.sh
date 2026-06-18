#!/usr/bin/env bash
# Ensures a STABLE local code-signing identity exists, so macOS TCC grants
# (Accessibility, Input Monitoring) survive rebuilds. Ad-hoc signing changes the
# code hash every build, which silently revokes those grants.
#
# Creates a dedicated keychain with a self-signed code-signing certificate. Fully
# non-interactive — no login-keychain password, no GUI prompts. Idempotent.
#
# On success prints (quoted, eval-friendly) to stdout:
#   SIGN_IDENTITY='Claude Footswitch Local'
#   SIGN_KEYCHAIN='/Users/.../claude-footswitch-codesign.keychain-db'
set -euo pipefail

IDENTITY="Claude Footswitch Local"
KEYCHAIN="$HOME/Library/Keychains/claude-footswitch-codesign.keychain-db"
KC_PASS="footswitch-local-signing"

log() { echo "$@" >&2; }

if [ ! -f "$KEYCHAIN" ]; then
    log "▸ Creating local signing keychain…"
    security create-keychain -p "$KC_PASS" "$KEYCHAIN"
fi
security set-keychain-settings "$KEYCHAIN"            # no auto-lock / timeout
security unlock-keychain -p "$KC_PASS" "$KEYCHAIN"

# NB: no -v here — a self-signed cert is untrusted ("not valid"), but codesign can still
# use it. Checking valid-only would regenerate a duplicate identity on every run.
if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    log "▸ Generating self-signed code-signing certificate “$IDENTITY”…"
    tmp="$(mktemp -d)"
    cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $IDENTITY
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -config "$tmp/cert.cnf" >/dev/null 2>&1
    # -legacy: OpenSSL 3 otherwise uses a PKCS#12 MAC that Apple's `security` can't verify.
    openssl pkcs12 -export -legacy -name "$IDENTITY" \
        -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
        -out "$tmp/identity.p12" -passout pass:"$KC_PASS" >/dev/null 2>&1
    # -A: any app may use the key; -T codesign: explicitly allow codesign.
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$KC_PASS" -A -T /usr/bin/codesign >/dev/null 2>&1
    # Pre-authorize codesign so it never shows a keychain-access prompt.
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KC_PASS" "$KEYCHAIN" >/dev/null 2>&1 || true
    rm -rf "$tmp"
    log "✓ Created “$IDENTITY”."
fi

# codesign locates the identity via the keychain search list — make sure ours is on it
# (append, preserving the user's existing keychains).
current="$(security list-keychains -d user | sed -e 's/^[[:space:]]*//' -e 's/"//g')"
if ! printf '%s\n' "$current" | grep -qF "$KEYCHAIN"; then
    log "▸ Adding signing keychain to the search list…"
    security list-keychains -d user -s $current "$KEYCHAIN"
fi

echo "SIGN_IDENTITY='$IDENTITY'"
echo "SIGN_KEYCHAIN='$KEYCHAIN'"
