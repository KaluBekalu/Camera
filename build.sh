#!/bin/bash
# Builds Camera.app from the Swift sources using the Command Line Tools
# toolchain (no full Xcode required). Produces ./build/Camera.app and
# ad-hoc code-signs it so macOS grants it a stable TCC identity.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Camera"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
MACOS_DIR="$APP/Contents/MacOS"
SWIFTC="${SWIFTC:-}"
if [ -z "$SWIFTC" ]; then
    if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
        SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
    else
        SWIFTC="$(xcrun -f swiftc)"
    fi
fi
ARCH="$(uname -m)"

# Pick the newest installed Command Line Tools macOS SDK.
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)"
[ -z "$SDK" ] && SDK="$(xcrun --show-sdk-path --sdk macosx)"

echo "→ Using SDK: $SDK"

rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$APP/Contents/Resources"

echo "→ Compiling…"
"$SWIFTC" \
    -sdk "$SDK" \
    -target "$ARCH-apple-macosx14.0" \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -o "$MACOS_DIR/$APP_NAME" \
    "$ROOT"/Sources/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

echo "→ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Run it with:  open \"$APP\""
