#!/bin/bash
# Compiles CaptureGeometry + its tests with the CLT toolchain and runs them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

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
ARCH="$(uname -m)"

mkdir -p "$ROOT/build"
"$SWIFTC" -sdk "$SDK" -target "$ARCH-apple-macosx14.0" -swift-version 5 -parse-as-library \
    -o "$ROOT/build/capture-geometry-tests" \
    "$ROOT/Sources/CaptureGeometry.swift" "$ROOT/Tests/CaptureGeometryTests.swift"
exec "$ROOT/build/capture-geometry-tests"
