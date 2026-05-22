#!/usr/bin/env bash
# bin/reset-alpha.sh — DESTRUCTIVE wipe and re-bootstrap.
#
# Brings everything down and removes the Postgres + Redis data volumes, then
# runs bin/run-alpha.sh fresh. Use this when you want to clear all memories,
# all diary entries, the seen-set, the reflection counter — start clean.
#
# Pass --force / -f to skip the interactive confirmation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/harness/lib.sh"

force=0
for arg in "$@"; do
    case "$arg" in
        -f|--force|--yes|-y) force=1 ;;
        -h|--help)
            cat <<EOF
Usage: bin/reset-alpha.sh [--force]

DESTRUCTIVE. Removes alpha-dev-pgdata and alpha-dev-redis volumes; all
stored memories, diary entries, and ephemeral session state are erased.
After wipe, schema is re-applied and alpha-server is restarted.

Options:
  -f, --force, --yes      Skip the interactive confirmation.
  -h, --help              Show this help.
EOF
            exit 0
            ;;
        *)
            fail "Unknown argument: $arg"
            exit 1
            ;;
    esac
done

hdr "Confirm destructive reset"

cat <<EOF
This will:
  - Stop alpha-server.
  - Run \`docker compose -f compose-dev.yml down -v\` (removes data volumes).
  - Drop ALL memories, ALL diary entries, ALL Redis state.
  - Re-bootstrap by calling bin/run-alpha.sh.

Volumes that will be removed:
  - alpha-dev-pgdata
  - alpha-dev-redis
EOF

if (( ! force )); then
    echo
    read -rp "Type 'reset' to proceed: " confirm
    if [[ "$confirm" != "reset" ]]; then
        echo "Aborted."
        exit 1
    fi
fi

hdr "Stopping alpha-server (if running)"
bash "$REPO_ROOT/harness/down.sh" || true

hdr "Removing data volumes"
docker compose -f "$REPO_ROOT/compose-dev.yml" down -v
ok "compose down -v complete"

hdr "Re-bootstrapping via bin/run-alpha.sh"
exec bash "$REPO_ROOT/bin/run-alpha.sh"
