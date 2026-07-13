#!/usr/bin/env bash
# Build ClaudePulse i sklopi ga u ClaudePulse.app (ad-hoc potpisan).
# Nema Xcode-a → sve preko `swift build` (ADR-001).
set -euo pipefail

# Koren repoa (skripta je u scripts/).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="$ROOT/app"
APP_NAME="ClaudePulse"
BUNDLE_ID="com.marko.claudepulse"
VERSION="0.0.1"

APP_BUNDLE="$ROOT/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RES_DIR="$CONTENTS/Resources"

echo "==> swift build -c release"
( cd "$APP_SRC" && swift build -c release )

BIN_PATH="$( cd "$APP_SRC" && swift build -c release --show-bin-path )/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
    echo "GREŠKA: binary nije pronađen na $BIN_PATH" >&2
    exit 1
fi

echo "==> sklapam $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign (potrebno za UNUserNotificationCenter u Phase 3)"
codesign --force --sign - "$APP_BUNDLE"

echo "==> gotovo: $APP_BUNDLE"
