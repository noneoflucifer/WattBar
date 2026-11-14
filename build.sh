#!/bin/bash
# Build PowerWatch.app from source.
# Requirements: macOS 13+ and Xcode Command Line Tools (swiftc).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/PowerWatch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cp Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
  -framework AppKit -framework SwiftUI -framework Security \
  -o "$APP/Contents/MacOS/PowerWatch" \
  PowerWatch.swift

codesign --force --sign - "$APP"
echo "Built: $APP"
echo "Run with: open \"$APP\""
