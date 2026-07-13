#!/usr/bin/env bash
#
# install-hooks.sh — ClaudePulse Claude Code hooks installer (Phase 5, §2.6, ADR-011)
#
# Spaja (jq merge, NIKAD overwrite) ClaudePulse status-hookove u ~/.claude/settings.json:
#
#   UserPromptSubmit → busy      PreToolUse   → busy (osvežava TTL)
#   Notification     → waiting    Stop         → done
#
# Svaka komanda je fail-silent (`|| true`) da hook nikad ne obori Claude Code, i nosi
# marker `# claudepulse` po kome se prepoznaje pri uninstall-u / re-install-u. Custom
# hookovi korisnika ostaju netaknuti. Pre svake izmene pravi se timestamped backup, a
# upis je atomičan (temp → jq validacija → mv).
#
# Upotreba:
#   bash install-hooks.sh [--port N]     # instalira (default port 4242)
#   bash install-hooks.sh --uninstall    # uklanja samo ClaudePulse hookove
#   bash install-hooks.sh --help

set -euo pipefail

# --- Konstante ------------------------------------------------------------------------

DEFAULT_PORT=4242
MARKER="claudepulse"                         # substring koji obeležava naše hookove
SETTINGS="$HOME/.claude/settings.json"
CLAUDE_DIR="$HOME/.claude"

# --- Argumenti ------------------------------------------------------------------------

PORT="$DEFAULT_PORT"
MODE="install"

usage() {
    cat <<EOF
ClaudePulse — Claude Code hooks installer

Usage:
  bash install-hooks.sh [--port N]     Install hooks (default port ${DEFAULT_PORT})
  bash install-hooks.sh --uninstall    Remove only ClaudePulse hooks
  bash install-hooks.sh --help         Show this help

Merges into ~/.claude/settings.json (never overwrites). A timestamped backup is
created before any change. Re-running install is idempotent (no duplicates).
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --port)
            [ $# -ge 2 ] || { echo "error: --port requires a value" >&2; exit 1; }
            PORT="$2"
            shift 2
            ;;
        --port=*)
            PORT="${1#*=}"
            shift
            ;;
        --uninstall)
            MODE="uninstall"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument: $1" >&2
            echo >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
    echo "error: --port must be an integer in 1..65535 (got: $PORT)" >&2
    exit 1
fi

# --- Preduslovi -----------------------------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
    echo "error: 'jq' is required but not found." >&2
    echo "       Install it with:  brew install jq" >&2
    exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    echo "error: 'curl' is required but not found." >&2
    exit 1
fi

# --- Pomoćne funkcije -----------------------------------------------------------------

# jq filter koji uklanja sve naše hook-grupe iz svakog event-a. Deli ga install (pre
# dodavanja svežih) i uninstall. Čuva sve što nije naše: model/theme/custom hookove.
# Za svaki event: izbaci grupe u kojima BILO KOJA komanda sadrži marker; ako event
# ostane prazan niz → obriši ključ; ako `.hooks` ostane prazan objekat → obriši ga.
read -r -d '' REMOVE_FILTER <<'JQ' || true
def strip_marker(ev; mark):
    if (.hooks[ev] | type) == "array" then
        .hooks[ev] |= map(select(
            [ (.hooks // [])[] | .command? // "" | contains(mark) ] | any | not
        ))
        | (if (.hooks[ev] | length) == 0 then del(.hooks[ev]) else . end)
    else . end;

if (.hooks | type) == "object" then
    strip_marker("UserPromptSubmit"; $mark)
    | strip_marker("PreToolUse"; $mark)
    | strip_marker("Notification"; $mark)
    | strip_marker("Stop"; $mark)
    | (if (.hooks | length) == 0 then del(.hooks) else . end)
else . end
JQ

# jq filter koji dodaje sveže ClaudePulse grupe (posle REMOVE-a). Komande se grade od
# $cmd_* argumenata (port već ubrizgan u bash-u, bez string-lepljenja u jq-u).
read -r -d '' ADD_FILTER <<'JQ' || true
.hooks //= {}
| .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [ { hooks: [ { type: "command", command: $cmd_busy } ] } ])
| .hooks.PreToolUse       = ((.hooks.PreToolUse // [])       + [ { matcher: "", hooks: [ { type: "command", command: $cmd_busy } ] } ])
| .hooks.Notification     = ((.hooks.Notification // [])     + [ { hooks: [ { type: "command", command: $cmd_waiting } ] } ])
| .hooks.Stop             = ((.hooks.Stop // [])             + [ { hooks: [ { type: "command", command: $cmd_done } ] } ])
JQ

# Gradi curl komandu za dati state (single-line, fail-silent, sa markerom).
build_cmd() {
    local state="$1"
    printf "curl -s -m 2 -X POST http://127.0.0.1:%s/status -H 'Content-Type: application/json' -d '{\"source\":\"code\",\"state\":\"%s\"}' >/dev/null 2>&1 || true  # %s" \
        "$PORT" "$state" "$MARKER"
}

# Atomičan upis: validira JSON pa mv preko originala. $1 = sadržaj (string).
write_settings() {
    local content="$1"
    local tmp
    tmp="$(mktemp "${SETTINGS}.tmp.XXXXXX")"
    printf '%s\n' "$content" > "$tmp"
    if ! jq empty "$tmp" >/dev/null 2>&1; then
        rm -f "$tmp"
        echo "error: produced invalid JSON — aborting, settings.json untouched." >&2
        exit 1
    fi
    mv "$tmp" "$SETTINGS"
}

# --- Učitavanje trenutnog sadržaja ----------------------------------------------------

mkdir -p "$CLAUDE_DIR"

if [ -f "$SETTINGS" ]; then
    if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
        echo "error: $SETTINGS is not valid JSON. Fix or move it before running." >&2
        exit 1
    fi
    CURRENT="$(cat "$SETTINGS")"
    # Backup pre ijedne izmene.
    BACKUP="${SETTINGS}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$SETTINGS" "$BACKUP"
    echo "Backup: $BACKUP"
else
    if [ "$MODE" = "uninstall" ]; then
        echo "Nothing to do: $SETTINGS does not exist."
        exit 0
    fi
    CURRENT='{}'
    echo "Note: $SETTINGS did not exist — creating it."
fi

# --- Izvršavanje ----------------------------------------------------------------------

if [ "$MODE" = "uninstall" ]; then
    RESULT="$(printf '%s' "$CURRENT" | jq --arg mark "$MARKER" "$REMOVE_FILTER")"
    write_settings "$RESULT"
    echo "Removed all ClaudePulse hooks. Custom hooks and other settings preserved."
    exit 0
fi

# install: ukloni naše (idempotencija) pa dodaj sveže.
CMD_BUSY="$(build_cmd busy)"
CMD_WAITING="$(build_cmd waiting)"
CMD_DONE="$(build_cmd done)"

RESULT="$(printf '%s' "$CURRENT" \
    | jq --arg mark "$MARKER" "$REMOVE_FILTER" \
    | jq \
        --arg cmd_busy "$CMD_BUSY" \
        --arg cmd_waiting "$CMD_WAITING" \
        --arg cmd_done "$CMD_DONE" \
        "$ADD_FILTER")"

write_settings "$RESULT"

echo "Installed ClaudePulse hooks (port $PORT):"
echo "  UserPromptSubmit → busy    PreToolUse → busy"
echo "  Notification     → waiting  Stop       → done"

# --- Verify (best effort) -------------------------------------------------------------

if curl -s -m 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo "ClaudePulse app is reachable on port $PORT. ✓"
else
    echo "Note: ClaudePulse app not reachable on port $PORT — start it, then hooks will work."
fi
