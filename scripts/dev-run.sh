#!/usr/bin/env bash
# Build + (re)pokreni ClaudePulse.app tokom razvoja.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ClaudePulse"

bash "$ROOT/scripts/build-app.sh"

echo "==> gasim prethodnu instancu (ako postoji)"
pkill -f "$APP_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true

echo "==> pokrećem $APP_NAME.app"
open "$ROOT/$APP_NAME.app"
echo "==> ikona bi trebalo da je vidljiva u menu baru (gore desno)"
