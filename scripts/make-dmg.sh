#!/usr/bin/env bash
# Napravi .dmg installer sa klasičnim "prevuci ClaudePulse u Applications" prozorom.
# Zero-dep: samo `hdiutil` (ugrađen u macOS). Ne zahteva create-dmg ni Xcode.
#
#   bash scripts/make-dmg.sh            # verzija 1.0.0
#   bash scripts/make-dmg.sh 1.2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudePulse"
VERSION="${1:-1.0.0}"

APP_BUNDLE="$ROOT/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-v$VERSION.dmg"
VOL_NAME="$APP_NAME"

echo "==> release build (CLAUDEPULSE_VERSION=$VERSION)"
CLAUDEPULSE_VERSION="$VERSION" bash "$ROOT/scripts/build-app.sh"

echo "==> provera ad-hoc potpisa"
codesign --verify --deep --strict "$APP_BUNDLE"

# Staging folder = tačno ono što korisnik vidi kad otvori DMG:
#   ClaudePulse.app  +  prečica na /Applications  → drag-and-drop instalacija.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
echo "==> pripremam sadržaj DMG-a"
cp -R "$APP_BUNDLE" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

echo "==> pravim $DMG_PATH"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
# UDZO = kompresovan, read-only DMG (finalni format za distribuciju).
hdiutil create \
    -volname "$VOL_NAME" \
    -srcfolder "$STAGE" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

echo "==> potpisujem DMG (ad-hoc)"
codesign --force --sign - "$DMG_PATH" 2>/dev/null || true

SHA_PATH="$DMG_PATH.sha256"
( cd "$DIST_DIR" && shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$SHA_PATH")" )
SIZE="$(du -h "$DMG_PATH" | awk '{print $1}')"

cat <<SUMMARY

==> gotovo
    DMG    : $DMG_PATH ($SIZE)
    sha256 : $(awk '{print $1}' "$SHA_PATH")

Korisnik: dupli klik na .dmg → prevuče ClaudePulse u Applications. (Prvi start:
right-click → Open, jer app nije notarizovan — vidi README / TROUBLESHOOTING.)

Dodaj na postojeći Release:
    gh release upload v$VERSION "$DMG_PATH" "$SHA_PATH" --repo remati037/claude-pulse
SUMMARY
