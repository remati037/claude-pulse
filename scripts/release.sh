#!/usr/bin/env bash
# Napravi distribucioni artefakt: release build → zip → SHA-256 (Phase 7, ADR-013).
# Zero-dep: samo macOS alati (swift/codesign/ditto/shasum). GitHub Release se NE pravi
# ovde — skripta na kraju ispiše predloženu `gh release create` komandu (outward akcija).
#
#   bash scripts/release.sh            # verzija 1.0.0
#   bash scripts/release.sh 1.2.0      # eksplicitna verzija
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudePulse"
VERSION="${1:-1.0.0}"

APP_BUNDLE="$ROOT/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
ZIP_PATH="$DIST_DIR/$APP_NAME-v$VERSION.zip"
SHA_PATH="$ZIP_PATH.sha256"

echo "==> release verzija: $VERSION"

# Verzija se stamp-uje u Info.plist kroz build-app.sh (jedini izvor istine).
echo "==> build + bundle (CLAUDEPULSE_VERSION=$VERSION)"
CLAUDEPULSE_VERSION="$VERSION" bash "$ROOT/scripts/build-app.sh"

echo "==> provera ad-hoc potpisa pre pakovanja"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "==> pakujem u $ZIP_PATH (ditto — čuva bundle strukturu + potpis)"
mkdir -p "$DIST_DIR"
rm -f "$ZIP_PATH" "$SHA_PATH"
# --keepParent: zip sadrži ClaudePulse.app/ kao top-level, ne njegov sadržaj razliven.
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> SHA-256"
# Zapiši samo basename u .sha256 da `shasum -c` radi iz bilo kog direktorijuma.
( cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")" > "$(basename "$SHA_PATH")" )

SHA="$(awk '{print $1}' "$SHA_PATH")"
SIZE="$(du -h "$ZIP_PATH" | awk '{print $1}')"

cat <<SUMMARY

==> gotovo
    artefakt : $ZIP_PATH ($SIZE)
    sha256   : $SHA
    checksum : $SHA_PATH

Sledeći korak — objavi GitHub Release (outward, pokreni ručno kad si spreman):

    gh release create v$VERSION "$ZIP_PATH" "$SHA_PATH" \\
        --repo remati037/claude-pulse \\
        --title "ClaudePulse v$VERSION" \\
        --notes "macOS menu bar app: Claude Code + claude.ai + Claude Desktop status."

Krajnji korisnici onda instaliraju sa:

    curl -fsSL https://raw.githubusercontent.com/remati037/claude-pulse/master/scripts/install.sh | bash
SUMMARY
