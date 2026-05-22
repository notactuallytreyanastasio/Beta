#!/usr/bin/env bash
# bin/stop-alpha.sh — graceful teardown of everything bin/run-alpha.sh started.
#
# - Kills alpha-server (via the PID file the run script wrote).
# - Stops the dev compose stack.
# - Data volumes are PRESERVED. Use bin/reset-alpha.sh to wipe them.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/harness/lib.sh"

# Delegate to harness/down.sh, which handles the PID-file + compose-down dance.
bash "$REPO_ROOT/harness/down.sh"

echo
echo "${BOLD}Stopped.${RESET} Data volumes preserved; bin/run-alpha.sh will pick up where you left off."
