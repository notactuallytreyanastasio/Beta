#!/usr/bin/env bash
# bin/run-alpha.sh — bring Alpha + deciduous up end-to-end from one checkout.
#
# What this script does, in order:
#   1. Sanity-check prerequisites (docker, uv, deciduous, curl).
#   2. If .env is missing, copy .env.example to .env and pause for editing.
#   3. Bring up the dev compose stack (Postgres + pgvector + Redis).
#   4. Wait for Postgres to accept connections.
#   5. Apply schema/cortex-bootstrap.sql (idempotent) so the cortex.* tables
#      exist with the columns the code expects.
#   6. If .env has real (non-placeholder) keys, start alpha-server in the
#      background. Otherwise stay in substrate-only mode.
#   7. If the Alpha-System-Prompts sibling repo is cloned, render the legacy
#      system prompts into docs/system-prompts/.
#   8. Print the harness status one-screen.
#
# Re-running is safe. Stop everything with bin/stop-alpha.sh; wipe with
# bin/reset-alpha.sh.

set -euo pipefail

# Resolve repo root from this script's location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# Share the harness helpers (ANSI, listening, livez_ok, compose_up, ...).
source "$REPO_ROOT/harness/lib.sh"

# When .env still has any of these tokens, run substrate-only. The Ollama
# defaults in .env.example don't include them — they're real, working values.
PLACEHOLDER_RE='PUT-YOUR-|REPLACE-ME|FIXME'

# ---------------------------------------------------------------------------
# Step 1 — prerequisites
# ---------------------------------------------------------------------------
hdr "1/8  Checking prerequisites"

missing=0
for bin in docker uv curl python3; do
    if have "$bin"; then ok "$bin"
    else fail "$bin (not on PATH)"; missing=$((missing+1))
    fi
done
if have deciduous; then ok "deciduous"
else warn "deciduous (not on PATH — the .claude/ deciduous workflow will be disabled but Alpha will still come up)"
fi

if (( missing > 0 )); then
    fail "Missing $missing required tool(s). Install them and re-run."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    fail "docker daemon is not running. Start Docker Desktop (or your daemon) and re-run."
    exit 1
fi
ok "docker daemon is running"

# ---------------------------------------------------------------------------
# Step 2 — .env file
# ---------------------------------------------------------------------------
hdr "2/8  .env"

env_file="$REPO_ROOT/.env"
env_example="$REPO_ROOT/.env.example"

if [[ ! -f "$env_file" ]]; then
    if [[ -f "$env_example" ]]; then
        cp "$env_example" "$env_file"
        ok "Copied .env.example to .env"
        warn "Open .env and replace the PUT-YOUR-... placeholders with real keys."
        warn "Substrate-only mode will run now; alpha-server will skip until you edit .env."
    else
        fail "Neither .env nor .env.example exists. Re-run scripts/bootstrap."
        exit 1
    fi
else
    ok ".env present"
fi

# Detect placeholders.
if grep -q "$PLACEHOLDER_RE" "$env_file"; then
    substrate_only=1
    warn ".env still has PUT-YOUR-... placeholders — running substrate-only (no alpha-server)."
else
    substrate_only=0
    ok ".env has real values"
fi

# ---------------------------------------------------------------------------
# Step 3 — dev compose stack
# ---------------------------------------------------------------------------
hdr "3/8  Dev compose stack (Postgres + Redis)"

docker compose -f "$REPO_ROOT/compose-dev.yml" up -d
ok "compose-dev.yml up"

# ---------------------------------------------------------------------------
# Step 4 — wait for Postgres
# ---------------------------------------------------------------------------
hdr "4/8  Waiting for Postgres"

ready=0
for i in $(seq 1 30); do
    if docker compose -f "$REPO_ROOT/compose-dev.yml" exec -T postgres \
         pg_isready -U postgres >/dev/null 2>&1; then
        ok "postgres ready (after ${i}s)"
        ready=1
        break
    fi
    sleep 1
done
if (( ! ready )); then
    fail "Postgres never came ready. Check 'docker compose -f compose-dev.yml logs postgres'."
    exit 1
fi

if listening 127.0.0.1 6379; then ok "redis listening on :6379"; fi

# ---------------------------------------------------------------------------
# Step 5 — apply schema
# ---------------------------------------------------------------------------
hdr "5/8  Applying cortex schema (idempotent)"

schema_file="$REPO_ROOT/schema/cortex-bootstrap.sql"
if [[ ! -f "$schema_file" ]]; then
    fail "Missing $schema_file"
    exit 1
fi

# Apply the schema. The SQL is idempotent (CREATE EXTENSION/SCHEMA/TABLE IF
# NOT EXISTS, CREATE INDEX IF NOT EXISTS) so running this every time is fine.
# ON_ERROR_STOP=1 makes psql exit non-zero on the first failing statement
# instead of plowing through and reporting overall success.
if docker compose -f "$REPO_ROOT/compose-dev.yml" exec -T postgres \
     psql --quiet --no-align --tuples-only \
          --set ON_ERROR_STOP=1 \
          --username=postgres --dbname=postgres \
          < "$schema_file" >/dev/null; then
    ok "schema applied"
else
    fail "psql apply failed. Re-run to see the error, or attach a shell:"
    fail "    docker compose -f compose-dev.yml exec postgres psql -U postgres"
    exit 1
fi

# Quick sanity probe.
n_tables=$(docker compose -f "$REPO_ROOT/compose-dev.yml" exec -T postgres \
    psql --quiet --no-align --tuples-only \
         --username=postgres --dbname=postgres \
         -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'cortex'" \
    2>/dev/null | tr -d '[:space:]')
ok "cortex schema has ${n_tables} table(s) — memories, diary"

# ---------------------------------------------------------------------------
# Step 5b — local model servers (Ollama + llama-server embeddings)
# ---------------------------------------------------------------------------
get_env() {
    local key="$1"
    grep -m1 -E "^${key}=" "$env_file" 2>/dev/null \
        | sed -E "s/^${key}=//" \
        | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}

chat_base_url="$(get_env chat_base_url)"
embedding_base_url="$(get_env embedding_base_url)"

# If chat points at Ollama, warn on missing chat model.
if [[ "$chat_base_url" == *":11434"* ]]; then
    hdr "5b/8  Ollama (chat)"
    if curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
        installed=$(curl -fsS http://localhost:11434/api/tags \
            | python3 -c 'import json,sys; print("\n".join(m["name"] for m in json.load(sys.stdin)["models"]))' \
            2>/dev/null || true)
        cm="$(get_env chat_model)"
        if [[ -n "$cm" ]]; then
            if grep -qx -F "$cm" <<<"$installed"; then
                ok "chat_model=$cm (present)"
            else
                warn "chat_model=$cm (NOT pulled — run: just alpha-pull)"
            fi
        fi
    else
        warn "Ollama not reachable at localhost:11434 — start 'ollama serve' or open the Ollama app."
    fi
fi

# If embeddings point at port 11436, that's the llama-server slot. Start it
# if it's not already up. (Ollama-served embeddings at 11434 are left alone.)
if [[ "$embedding_base_url" == *":11436"* ]]; then
    hdr "5c/8  llama-server (embeddings)"
    if listening 127.0.0.1 11436; then
        ok "llama-server already listening on :11436"
    else
        if bash "$REPO_ROOT/bin/start-embed-server.sh"; then
            :
        else
            warn "Failed to start llama-server. alpha-server will start but"
            warn "Cortex tools that embed (store_memory, search_memories) will error."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Step 6 — alpha-server
# ---------------------------------------------------------------------------
hdr "6/8  alpha-server"

if (( substrate_only )); then
    warn "Skipping alpha-server (substrate-only mode)."
    warn "When you've edited .env with real keys, re-run this script."
else
    if listening 127.0.0.1 8000; then
        ok "alpha-server already listening on :8000"
    else
        echo "  starting alpha-server in background (log: harness/alpha-server.log)"
        (
            cd "$REPO_ROOT/alpha-server"
            # Ensure deps are installed.
            if [[ ! -d ".venv" ]]; then
                echo "  installing alpha-server dependencies via 'uv sync --all-extras'..."
                uv sync --all-extras >/dev/null 2>&1
            fi
            nohup uv run uvicorn alpha_server.app:app \
                --host 127.0.0.1 --port 8000 \
                >"$REPO_ROOT/harness/alpha-server.log" 2>&1 &
            echo $! > "$REPO_ROOT/harness/alpha-server.pid"
        )

        # Wait for /livez.
        booted=0
        for i in $(seq 1 30); do
            if livez_ok; then
                ok "alpha-server /livez OK (after ${i}s)"
                booted=1
                break
            fi
            sleep 1
        done
        if (( ! booted )); then
            warn "alpha-server didn't come up cleanly. Tail the log:"
            warn "    tail -f harness/alpha-server.log"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Step 7 — render system prompts (best effort)
# ---------------------------------------------------------------------------
hdr "7/8  System prompts (Alpha-System-Prompts)"

if [[ -n "$ALPHA_SYSPROMPTS" ]]; then
    bash "$REPO_ROOT/harness/render-prompts.sh" || warn "prompt render failed (non-fatal)"
else
    warn "Alpha-System-Prompts not cloned beside this repo — skipping prompt render."
    warn "To enable:  cd .. && gh repo clone jefferyharrell/Alpha-System-Prompts"
fi

# ---------------------------------------------------------------------------
# Step 8 — status
# ---------------------------------------------------------------------------
hdr "8/8  Final status"

bash "$REPO_ROOT/harness/status.sh"

echo
echo "${BOLD}Done.${RESET} Open Claude Code in this directory and you should land in Alpha's .claude/."
echo "    open ${REPO_ROOT}"
if (( substrate_only )); then
    echo
    echo "${YELLOW}Substrate-only:${RESET} edit .env with real keys, then re-run:"
    echo "    bin/run-alpha.sh"
fi
echo
echo "Stop:   bin/stop-alpha.sh"
echo "Reset:  bin/reset-alpha.sh   (WIPES all data volumes)"
