# Alpha dev environment recipes.
# Run from the repo root: `just <recipe>`.

# List recipes.
default:
    @just --list

# Start the dev environment (Postgres and Redis, both on localhost).
dev-up:
    docker compose -f compose-dev.yml up -d

# Stop the dev environment (preserves the data volumes).
dev-down:
    docker compose -f compose-dev.yml down

# Wipe Postgres AND Redis data volumes, bring services up fresh, restore Postgres from a dump.
dev-init dump:
    docker compose -f compose-dev.yml down -v
    docker compose -f compose-dev.yml up -d
    @echo "(waiting for postgres to accept connections)"
    @until docker compose -f compose-dev.yml exec -T postgres pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
    docker compose -f compose-dev.yml exec -T postgres pg_restore \
        --username=postgres \
        --dbname=postgres \
        --single-transaction \
        --no-owner \
        --no-acl \
        < {{dump}}

# === Alpha + deciduous harness ===
# These recipes orchestrate the full stack: dev DB, alpha-server, system-prompts,
# and the merged .claude/ config. See harness/README.md for the integration story.

# Pre-flight: report what's needed and what's present.
harness-doctor:
    @bash harness/doctor.sh

# One-screen "is it up?" status across all layers.
harness-status:
    @bash harness/status.sh

# Bring it all up: dev stack + alpha-server (if .env present) + render prompts.
harness-up:
    @bash harness/up.sh

# Graceful teardown (data volumes preserved).
harness-down:
    @bash harness/down.sh

# Pull the latest .claude/ payload from the sibling Alpha-dotclaude checkout
# into THIS repo's .claude/. Preserves deciduous commands/hooks/skills; only
# overwrites Alpha-owned subtrees (agents/, context/, rules/, skills/start/).
harness-sync:
    @bash harness/sync.sh

# Just the alpha-server side (assumes dev stack is already up).
server-up:
    @bash -c 'cd alpha-server && nohup uv run uvicorn alpha_server.app:app --host 127.0.0.1 --port 8000 >../harness/alpha-server.log 2>&1 & echo $$! >../harness/alpha-server.pid'
    @echo "started alpha-server (pid $$(cat harness/alpha-server.pid))"

# Render Alpha-System-Prompts templates into docs/system-prompts/.
prompt-render:
    @bash harness/render-prompts.sh

# === bin/ one-shot orchestration (the easy buttons) ===
# These wrap bin/*.sh in just recipes so you don't have to remember the paths.

# One command to bring Alpha up: dev stack + schema + alpha-server + prompts.
alpha-up:
    @bash bin/run-alpha.sh

# Graceful stop. Volumes preserved.
alpha-down:
    @bash bin/stop-alpha.sh

# DESTRUCTIVE: wipe volumes and re-bootstrap. Confirms unless --force.
alpha-reset *args:
    @bash bin/reset-alpha.sh {{args}}

# Pull the Ollama models named in .env (chat_model + embedding_model).
# Idempotent — skips models already present.
alpha-pull:
    @bash bin/pull-models.sh

# Unified log tail — all four sources merged with colored prefixes.
# Pass --lines N to set how many historical lines to show (default 50).
# Pass --no-color for plain text (pipe-friendly).
alpha-logs *args:
    @bash bin/logs.sh {{args}}
