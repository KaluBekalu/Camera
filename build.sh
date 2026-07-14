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
SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"

# Pick the newest installed Command Line Tools macOS SDK.
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | sort -V | tail -1)"
[ -z "$SDK" ] && SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"

echo "→ Using SDK: $SDK"

rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$APP/Contents/Resources"

echo "→ Compiling…"
"$SWIFTC" \
    -sdk "$SDK" \
    -target arm64-apple-macosx14.0 \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -o "$MACOS_DIR/$APP_NAME" \
    "$ROOT"/Sources/*.swift

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "→ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Run it with:  open \"$APP\""
