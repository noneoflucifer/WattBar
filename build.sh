#!/bin/bash
# Build WattBar.app from source.
# Requirements: macOS 13+ and Xcode Command Line Tools (swiftc).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/WattBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Info.plist "$APP/Contents/Info.plist"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 \
  -framework AppKit -framework SwiftUI -framework Security \
  -o "$APP/Contents/MacOS/WattBar" \
  PowerWatch.swift

codesign --force --deep --sign - "$APP"
echo "Built: $APP"
echo "Run with: open \"$APP\""
