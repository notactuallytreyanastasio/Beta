#!/usr/bin/env bash
# Shared helpers for the Alpha + deciduous harness scripts.
# Sourced, not executed.

set -euo pipefail

# Resolve repo root regardless of where the script was invoked from.
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"

# Sibling-repo paths (cloned beside Alpha). Two tiers:
#   integrated — harness reads from them
#   reference  — documented, not required to be present
ALPHA_DOTCLAUDE="$(cd "$REPO_ROOT/../Alpha-dotclaude" 2>/dev/null && pwd || true)"
ALPHA_SYSPROMPTS="$(cd "$REPO_ROOT/../Alpha-System-Prompts" 2>/dev/null && pwd || true)"
AGENT_FLEET="$(cd "$REPO_ROOT/../agent-fleet" 2>/dev/null && pwd || true)"
LOOM_DOTCLAUDE="$(cd "$REPO_ROOT/../Loom-dotclaude" 2>/dev/null && pwd || true)"
CLAUDE_HOOKS="$(cd "$REPO_ROOT/../Claude-Hooks" 2>/dev/null && pwd || true)"
INTRO_REPO="$(cd "$REPO_ROOT/../Intro" 2>/dev/null && pwd || true)"
ALPHA_SDK="$(cd "$REPO_ROOT/../Alpha-SDK" 2>/dev/null && pwd || true)"
HOUSE_SDK="$(cd "$REPO_ROOT/../House-SDK" 2>/dev/null && pwd || true)"
PONDSIDE_SDK="$(cd "$REPO_ROOT/../pondside-sdk" 2>/dev/null && pwd || true)"

# ANSI colors (bypass when not a TTY).
if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; RESET=""
fi

ok()   { printf "  %sok%s  %s\n"   "$GREEN"  "$RESET" "$1"; }
warn() { printf "  %s..%s  %s\n"   "$YELLOW" "$RESET" "$1"; }
fail() { printf "  %sX%s   %s\n"   "$RED"    "$RESET" "$1"; }
hdr()  { printf "\n%s== %s ==%s\n" "$BOLD"   "$1"     "$RESET"; }

# Has a binary on PATH?
have() { command -v "$1" >/dev/null 2>&1; }

# Is a host:port accepting TCP?
listening() {
    local host="$1" port="$2"
    if have nc; then
        nc -z -G 1 "$host" "$port" >/dev/null 2>&1
    else
        (echo >"/dev/tcp/$host/$port") >/dev/null 2>&1
    fi
}

# Is alpha-server's /livez OK?
livez_ok() {
    have curl || return 1
    [[ "$(curl -fsS --max-time 2 http://127.0.0.1:8000/livez 2>/dev/null)" == *'"ok"'* ]]
}

# Is the dev compose stack up?
compose_up() {
    docker compose -f "$REPO_ROOT/compose-dev.yml" ps --status running --format '{{.Service}}' 2>/dev/null
}

# Pretty-print a key=value pair with alignment.
kv() {
    printf "  %-22s %s\n" "$1" "$2"
}
