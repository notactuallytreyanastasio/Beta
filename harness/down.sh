#!/usr/bin/env bash
# Graceful teardown:
#   1. stop alpha-server (PID file written by harness/up.sh)
#   2. stop dev stack
# Data volumes are preserved.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

hdr "Step 1 — alpha-server"
pid_file="$REPO_ROOT/harness/alpha-server.pid"
if [[ -f "$pid_file" ]]; then
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
        ok "stopped alpha-server (pid $pid)"
    else
        warn "PID $pid from $pid_file is not running"
    fi
    rm -f "$pid_file"
else
    # Fall back to any uvicorn that bound :8000.
    if listening 127.0.0.1 8000; then
        warn "no harness/alpha-server.pid; not killing — if you started it manually, stop it yourself"
    else
        ok "alpha-server not running"
    fi
fi

hdr "Step 2 — llama-server (embeddings, if running)"
bash "$REPO_ROOT/bin/stop-embed-server.sh"

hdr "Step 3 — dev stack"
docker compose -f "$REPO_ROOT/compose-dev.yml" down
ok "compose-dev.yml down (data volumes preserved)"
