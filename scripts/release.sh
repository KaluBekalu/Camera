#!/bin/bash
# Build, sign, notarize, and publish a Camera release from this Mac.
#
# Usage:
#   ./scripts/release.sh v1.2.0
#
# Needs:
#   - Full Xcode (for notarytool/stapler); auto-detected, or set DEVELOPER_DIR
#   - "Developer ID Application" identity in the login keychain
#   - An App Store Connect API key + issuer id for notarytool:
#       NOTARY_DIR (default: ~/dev/loopcam/certification) containing
#       AuthKey_<KEYID>.p8 and notary.env exporting NOTARY_ISSUER_ID
#   - gh CLI authenticated (release upload)
set -euo pipefail
cd "$(dirname "$0")/.."

TAG="${1:?usage: release.sh vX.Y.Z}"
VERSION="${TAG#v}"
APP_NAME="Camera"

# --- toolchain (notarytool/stapler need full Xcode) --------------------------
if [[ -z "${DEVELOPER_DIR:-}" ]] || [[ ! -d "${DEVELOPER_DIR:-}" ]]; then
    for candidate in /Applications/Xcode.app "/Volumes/PRO-G40/Apple Apps/Xcode.app" /Volumes/PRO-G40/Xcode.app; do
        [[ -d "$candidate" ]] && export DEVELOPER_DIR="$candidate" && break
    done
fi
xcrun -f notarytool >/dev/null 2>&1 || { echo "error: notarytool unavailable; set DEVELOPER_DIR=/path/to/Xcode.app" >&2; exit 1; }
SWIFTC="$(xcrun -f swiftc)"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
echo "Toolchain: $DEVELOPER_DIR"

# --- notary credentials ------------------------------------------------------
NOTARY_DIR="${NOTARY_DIR:-$HOME/dev/loopcam/certification}"
[[ -f "$NOTARY_DIR/notary.env" ]] && source "$NOTARY_DIR/notary.env"
: "${NOTARY_ISSUER_ID:?set NOTARY_ISSUER_ID or put it in \$NOTARY_DIR/notary.env}"
NOTARY_KEY=$(ls "$NOTARY_DIR"/AuthKey_*.p8 | head -1)
NOTARY_KEY_ID=$(basename "$NOTARY_KEY" .p8 | sed 's/^AuthKey_//')
echo "Notary key: $NOTARY_KEY_ID"

# --- identity ----------------------------------------------------------------
IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)
test -n "$IDENTITY" || { echo "error: no Developer ID Application identity in keychain" >&2; exit 1; }
echo "Signing as: $IDENTITY"

# --- build (universal: arm64 + x86_64) ---------------------------------------
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
APP="$TMP/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for ARCH in arm64 x86_64; do
    echo "→ Compiling $ARCH…"
    "$SWIFTC" -sdk "$SDK" -target "$ARCH-apple-macosx14.0" -swift-version 5 \
        -parse-as-library -O -o "$TMP/$APP_NAME-$ARCH" Sources/*.swift
done
lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "$TMP/$APP_NAME-arm64" "$TMP/$APP_NAME-x86_64"
lipo -info "$APP/Contents/MacOS/$APP_NAME"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"

# --- sign (hardened runtime + capture entitlements) --------------------------
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
    --entitlements Resources/Camera.entitlements "$APP"
codesign --verify --strict "$APP"
echo "Signed OK"

# --- notarize + staple app ---------------------------------------------------
ditto -c -k --keepParent "$APP" "$TMP/$APP_NAME-notarize.zip"
xcrun notarytool submit "$TMP/$APP_NAME-notarize.zip" \
    --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait --timeout 2h
xcrun stapler staple "$APP"

# --- dmg: build, sign, notarize, staple, assess ------------------------------
DMG="$APP_NAME-$TAG.dmg"
rm -rf "$TMP/dmg-root" "$DMG"
mkdir "$TMP/dmg-root"
cp -R "$APP" "$TMP/dmg-root/"
ln -s /Applications "$TMP/dmg-root/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$TMP/dmg-root" -ov -format UDZO "$DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" \
    --key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" --wait --timeout 2h
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "Gatekeeper OK: $DMG"

# --- GitHub release ----------------------------------------------------------
# A versionless Camera.dmg rides along so /releases/latest/download/Camera.dmg
# stays stable across versions (the site's Download button uses it).
git tag -f "$TAG" && git push -f origin "$TAG"
cp "$DMG" "$APP_NAME.dmg"
if gh release view "$TAG" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG" "$APP_NAME.dmg" --clobber
else
    gh release create "$TAG" "$DMG" "$APP_NAME.dmg" --title "$APP_NAME $TAG" --notes \
"$APP_NAME \`$TAG\` — signed with Developer ID and notarized by Apple. Universal (Apple silicon + Intel), macOS 14+.

Drag $APP_NAME into Applications and open it. macOS will ask for camera (and microphone) access on first launch.

Site: https://mac-camera.tibeblabs.com"
fi
rm -f "$APP_NAME.dmg"
echo "Release ready: $TAG"
