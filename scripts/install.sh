#!/usr/bin/env bash
# ClaudePulse one-line installer (Phase 7, ADR-013). Za krajnjeg korisnika:
#
#   curl -fsSL https://raw.githubusercontent.com/remati037/claude-pulse/master/scripts/install.sh | bash
#
# Skine latest GitHub Release, skine Gatekeeper karantin (xattr), instalira u /Applications
# i pokrene app. Zero-dep: samo alati koji postoje na čistom macOS-u (curl/unzip/xattr/shasum).
# NE dira `~/.claude/settings.json` — hookove korisnik instalira zasebno (vidi kraj).
set -euo pipefail

REPO="${CLAUDEPULSE_REPO:-remati037/claude-pulse}"
APP_NAME="ClaudePulse"
INSTALL_DIR="/Applications"
API="https://api.github.com/repos/$REPO/releases/latest"

echo "==> ClaudePulse installer (repo: $REPO)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> tražim latest release"
RELEASE_JSON="$(curl -fsSL "$API")"

# Bez jq (installer mora raditi na čistoj mašini): izvuci browser_download_url-ove grep-om.
ZIP_URL="$(printf '%s\n' "$RELEASE_JSON" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' \
    | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"
SHA_URL="$(printf '%s\n' "$RELEASE_JSON" \
    | grep -o '"browser_download_url": *"[^"]*\.zip\.sha256"' \
    | head -1 | sed 's/.*"browser_download_url": *"\([^"]*\)".*/\1/')"

if [[ -z "$ZIP_URL" ]]; then
    echo "GREŠKA: nema .zip asseta u latest release-u za $REPO." >&2
    echo "        Proveri https://github.com/$REPO/releases" >&2
    exit 1
fi

ZIP="$TMP/$APP_NAME.zip"
echo "==> skidam $ZIP_URL"
curl -fSL "$ZIP_URL" -o "$ZIP"

# Best-effort verifikacija checksuma ako release nosi .sha256 asset.
if [[ -n "$SHA_URL" ]]; then
    echo "==> verifikujem SHA-256"
    EXPECTED="$(curl -fsSL "$SHA_URL" | awk '{print $1}')"
    ACTUAL="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    if [[ "$EXPECTED" != "$ACTUAL" ]]; then
        echo "GREŠKA: SHA-256 se ne poklapa (očekivano $EXPECTED, dobijeno $ACTUAL)." >&2
        exit 1
    fi
    echo "    ok ($ACTUAL)"
fi

echo "==> raspakujem"
unzip -q "$ZIP" -d "$TMP/extracted"
NEW_APP="$TMP/extracted/$APP_NAME.app"
if [[ ! -d "$NEW_APP" ]]; then
    echo "GREŠKA: $APP_NAME.app nije nađen u arhivi." >&2
    exit 1
fi

echo "==> skidam Gatekeeper karantin (xattr)"
xattr -dr com.apple.quarantine "$NEW_APP" 2>/dev/null || true

DEST="$INSTALL_DIR/$APP_NAME.app"
if [[ -d "$DEST" ]]; then
    echo "==> gasim postojeću instancu i uklanjam staru verziju"
    pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    rm -rf "$DEST"
fi

echo "==> instaliram u $DEST"
mv "$NEW_APP" "$DEST"

echo "==> pokrećem $APP_NAME"
open "$DEST"

cat <<DONE

==> ClaudePulse je instaliran. Ikona je u menu baru (gore desno).

Poveži izvore:
  • Claude Code : curl -fsSL https://raw.githubusercontent.com/$REPO/master/hooks/install-hooks.sh | bash
                  (spaja hookove u ~/.claude/settings.json uz backup; zahteva jq)
  • claude.ai   : učitaj MV3 ekstenziju iz repoa (extension/) — vidi README.
  • Desktop app : odobri Accessibility permission na traženje (System Settings ▸ Privacy).

Problemi? https://github.com/$REPO/blob/master/docs/TROUBLESHOOTING.md
DONE
