#!/usr/bin/env bash
# bin/stop-embed-server.sh — stop the llama-server started by start-embed-server.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/harness/lib.sh"

PID_FILE="$REPO_ROOT/harness/embed-server.pid"

if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        ok "stopped llama-server (pid $pid)"
    else
        warn "PID $pid from $PID_FILE is not running"
    fi
    rm -f "$PID_FILE"
else
    ok "llama-server not running (no pid file)"
fi
