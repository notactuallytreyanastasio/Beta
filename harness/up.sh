#!/usr/bin/env bash
# Bring the full harness up:
#   1. dev stack (Postgres + Redis)
#   2. alpha-server (skipped if .env missing — substrate-only mode)
#   3. render system prompts (if Alpha-System-Prompts is present)
#   4. show status
#
# Idempotent: re-running is safe.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

hdr "Step 1 — dev stack (Postgres + Redis)"
docker compose -f "$REPO_ROOT/compose-dev.yml" up -d
echo "  (waiting for Postgres to accept connections)"
for _ in $(seq 1 30); do
    if docker compose -f "$REPO_ROOT/compose-dev.yml" exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
        ok "postgres ready"; break
    fi
    sleep 1
done
if listening 127.0.0.1 6379; then ok "redis listening on :6379"; fi

hdr "Step 2 — alpha-server"
if [[ -f "$REPO_ROOT/.env" ]] && grep -qiE '^\s*chat_api_key\s*=' "$REPO_ROOT/.env"; then
    if listening 127.0.0.1 8000; then
        ok "alpha-server already listening on :8000"
    else
        echo "  starting alpha-server in background (logs: harness/alpha-server.log)"
        (
            cd "$REPO_ROOT/alpha-server"
            nohup uv run uvicorn alpha_server.app:app --host 127.0.0.1 --port 8000 \
                >"$REPO_ROOT/harness/alpha-server.log" 2>&1 &
            echo $! > "$REPO_ROOT/harness/alpha-server.pid"
        )
        # Wait for /livez
        for _ in $(seq 1 30); do
            if livez_ok; then ok "alpha-server /livez OK"; break; fi
            sleep 1
        done
        livez_ok || warn "alpha-server didn't come up cleanly — tail harness/alpha-server.log"
    fi
else
    warn ".env missing or incomplete — running substrate-only (no alpha-server)."
    warn "Cortex/Utils tools and hook URLs will 404 until you provide a .env and rerun."
fi

hdr "Step 3 — render system prompts"
if [[ -n "$ALPHA_SYSPROMPTS" ]]; then
    bash "$HARNESS_DIR/render-prompts.sh"
else
    warn "Alpha-System-Prompts not cloned — skipping prompt render"
fi

echo
bash "$HARNESS_DIR/status.sh"
