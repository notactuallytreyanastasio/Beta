#!/usr/bin/env bash
# bin/pull-models.sh — pull the Ollama models alpha-server expects.
#
# Reads chat_model and embedding_model from .env (or .env.example) and
# `ollama pull`s each one. Skips models already present.
#
# Run this once after installing Ollama and before bin/run-alpha.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/harness/lib.sh"

if ! have ollama; then
    fail "ollama not on PATH. Install from https://ollama.com or 'brew install ollama'."
    exit 1
fi

# Make sure Ollama is reachable.
if ! curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
    fail "Ollama is not running on localhost:11434."
    fail "Start it with 'ollama serve' (or open the Ollama app)."
    exit 1
fi
ok "ollama is running"

# Read model names from .env if present, otherwise from .env.example.
env_source="$REPO_ROOT/.env"
if [[ ! -f "$env_source" ]]; then
    env_source="$REPO_ROOT/.env.example"
fi

get_env() {
    local key="$1"
    # Match `key=value` (no leading whitespace, no spaces around =). Strip
    # surrounding quotes if any. First match wins (so commented-out alternates
    # in .env.example don't override the live default).
    grep -m1 -E "^${key}=" "$env_source" 2>/dev/null \
        | sed -E "s/^${key}=//" \
        | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}

chat_model="$(get_env chat_model)"
embedding_model="$(get_env embedding_model)"

if [[ -z "$chat_model" || -z "$embedding_model" ]]; then
    fail "Could not read chat_model and embedding_model from $env_source"
    exit 1
fi

hdr "Models to ensure"
kv "chat_model"      "$chat_model"
kv "embedding_model" "$embedding_model"

# `ollama list` doesn't include the `:tag` portion in some versions; safer to
# query the HTTP API which returns full names including tags.
installed=$(curl -fsS http://localhost:11434/api/tags \
            | python3 -c 'import json,sys; print("\n".join(m["name"] for m in json.load(sys.stdin)["models"]))' \
            2>/dev/null || true)

needs_pull=()
for m in "$chat_model" "$embedding_model"; do
    if grep -qx -F "$m" <<<"$installed"; then
        ok "$m (already pulled)"
    else
        warn "$m (will pull)"
        needs_pull+=("$m")
    fi
done

if (( ${#needs_pull[@]} == 0 )); then
    echo
    echo "${BOLD}Nothing to do — both models already present.${RESET}"
    exit 0
fi

echo
echo "${BOLD}Pulling ${#needs_pull[@]} model(s).${RESET} This will take a while."
echo "    (Qwen 3 Embedding 4B :F16 is ~8GB; qwen2.5:7b is ~4.7GB)"
echo

for m in "${needs_pull[@]}"; do
    hdr "ollama pull $m"
    if ollama pull "$m"; then
        ok "pulled $m"
    else
        fail "pull failed for $m. If the tag is wrong, try 'ollama search ${m%%:*}' to find alternatives."
        exit 1
    fi
done

echo
echo "${BOLD}Done.${RESET} Verifying:"
ollama list
