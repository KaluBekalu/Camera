#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift.
# Requires only the Command Line Tools (swiftc + iconutil).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
        SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    else
        SWIFTC="$(xcrun -f swiftc)"
    fi
fi
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)"
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path --sdk macosx)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
"$SWIFTC" -sdk "$SDK" -O -o "$TMP/make-icon" "$ROOT/scripts/make-icon.swift"

SET="$TMP/AppIcon.iconset"
mkdir -p "$SET"
for entry in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 256:128x128@2x \
             256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
    px="${entry%%:*}"; name="${entry#*:}"
    "$TMP/make-icon" "$px" "$SET/icon_$name.png"
done
iconutil -c icns "$SET" -o "$ROOT/Resources/AppIcon.icns"
echo "✓ Wrote Resources/AppIcon.icns"
