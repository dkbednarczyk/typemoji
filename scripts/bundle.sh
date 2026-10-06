#!/bin/bash
# Builds build/typemoji.app from the SwiftPM package and signs it.
#
# Signs ad-hoc by default. Set CODESIGN_IDENTITY to a real identity (for
# example "Apple Development: you@example.com") so macOS keeps the
# Accessibility grant across rebuilds.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIGURATION="${CONFIGURATION:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/typemoji.app"

swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/typemoji" "$APP/Contents/MacOS/typemoji"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Resources/emoji.json "$APP/Contents/Resources/emoji.json"

codesign --force --sign "$IDENTITY" "$APP"
echo "Built $APP (signed with: $IDENTITY)"
