#!/usr/bin/env bash
# Render the app icon PNGs and pack them into Resources/AppIcon.icns.
set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET" docs

echo "▸ Rendering icon PNGs…"
swift tools/make-icon.swift "$ICONSET" "docs/icon.png"

echo "▸ Packing AppIcon.icns…"
iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns

echo "✓ Wrote Resources/AppIcon.icns and docs/icon.png"
