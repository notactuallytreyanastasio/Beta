#!/usr/bin/env bash
# bin/logs.sh — unified tail of every log source in the Alpha stack.
#
# Streams four sources merged into one output, each line prefixed and colored:
#
#   [alpha]    FastAPI process — hooks, MCP tool calls, errors
#   [embed]    llama-server  — embedding requests, model load, GGUF progress
#   [postgres] Postgres      — connections, slow queries, errors
#   [redis]    Redis          — commands, persistence saves
#
# Usage:
#   bin/logs.sh                # tail all sources from now
#   bin/logs.sh --lines 200    # start with last 200 lines of each file log
#   bin/logs.sh --no-color     # plain text (for piping to grep etc.)
#
# Requires: bash ≥ 4 (for process substitution), docker, tail.
# On macOS ship bash 3.2 from Apple — use the Homebrew bash 5 via
# #!/usr/bin/env bash if brew installed. Otherwise GNU tail is fine.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# ── options ─────────────────────────────────────────────────────────────────
LINES=50
COLOR=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lines|-n) LINES="$2"; shift 2 ;;
        --no-color) COLOR=0; shift ;;
        -h|--help)
            sed -n '3,12p' "$0"   # print the usage block from the header
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# ── ANSI colors ──────────────────────────────────────────────────────────────
if (( COLOR )); then
    C_ALPHA=$'\033[32m'      # green
    C_EMBED=$'\033[36m'      # cyan
    C_PG=$'\033[34m'         # blue
    C_REDIS=$'\033[35m'      # magenta
    C_RESET=$'\033[0m'
else
    C_ALPHA=''; C_EMBED=''; C_PG=''; C_REDIS=''; C_RESET=''
fi

# ── helpers ──────────────────────────────────────────────────────────────────
prefix() {
    # prefix LABEL COLOR  — read stdin and print each line with a label
    local label="$1" color="$2"
    local width=9   # pad label to consistent width
    local padded
    padded=$(printf "%-${width}s" "[$label]")
    while IFS= read -r line; do
        printf '%s%s%s %s\n' "$color" "$padded" "$C_RESET" "$line"
    done
}

# ── check what's actually running ────────────────────────────────────────────
alpha_log="$REPO_ROOT/harness/alpha-server.log"
embed_log="$REPO_ROOT/harness/embed-server.log"

pids=()

# alpha-server
if [[ -f "$alpha_log" ]]; then
    tail -n "$LINES" -f "$alpha_log" | prefix "alpha" "$C_ALPHA" &
    pids+=($!)
else
    echo "${C_ALPHA}[alpha]${C_RESET}   log not found: $alpha_log (server not yet started?)" &
fi

# llama-server (embed)
if [[ -f "$embed_log" ]]; then
    tail -n "$LINES" -f "$embed_log" | prefix "embed" "$C_EMBED" &
    pids+=($!)
else
    echo "${C_EMBED}[embed]${C_RESET}   log not found: $embed_log (embed server not yet started?)"
fi

# Postgres via docker compose (falls back gracefully if not running)
if docker compose -f "$REPO_ROOT/compose-dev.yml" ps --status running postgres \
        --format '{{.Service}}' 2>/dev/null | grep -q postgres; then
    docker compose -f "$REPO_ROOT/compose-dev.yml" logs -f --tail="$LINES" postgres 2>&1 \
        | prefix "postgres" "$C_PG" &
    pids+=($!)
else
    echo "${C_PG}[postgres]${C_RESET} container not running (just alpha-up to start it)"
fi

# Redis via docker compose
if docker compose -f "$REPO_ROOT/compose-dev.yml" ps --status running redis \
        --format '{{.Service}}' 2>/dev/null | grep -q redis; then
    docker compose -f "$REPO_ROOT/compose-dev.yml" logs -f --tail="$LINES" redis 2>&1 \
        | prefix "redis   " "$C_REDIS" &
    pids+=($!)
else
    echo "${C_REDIS}[redis]${C_RESET}    container not running (just alpha-up to start it)"
fi

# ── trap Ctrl-C and kill all children cleanly ────────────────────────────────
cleanup() {
    printf '\n'
    # Kill all background children. Suppress "Terminated" noise.
    for pid in "${pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
    wait 2>/dev/null
    exit 0
}
trap cleanup INT TERM

wait
