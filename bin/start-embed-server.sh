#!/usr/bin/env bash
# bin/start-embed-server.sh — start a local llama-server hosting the Qwen 3
# Embedding 4B GGUF, exposing an OpenAI-protocol /v1/embeddings endpoint.
#
# Why this exists: the Ollama community tag for Qwen 3 Embedding 4B is
# (currently) registered as a chat model, so /v1/embeddings returns 501
# against it. llama.cpp's llama-server has proper embedding support and
# keeps the codebase's hard-coded vector(2560) + Qwen "Instruct:" prefix
# working as-is.
#
# Reads:
#   EMBED_GGUF      Path to the GGUF file.
#                   Default: ~/llama-models/Qwen3-Embedding-4B-Q8_0.gguf
#   EMBED_PORT      Port to listen on.   Default: 11436
#   EMBED_HOST      Host to bind.        Default: 127.0.0.1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

source "$REPO_ROOT/harness/lib.sh"

EMBED_GGUF="${EMBED_GGUF:-$HOME/llama-models/Qwen3-Embedding-4B-Q8_0.gguf}"
EMBED_PORT="${EMBED_PORT:-11436}"
EMBED_HOST="${EMBED_HOST:-127.0.0.1}"

PID_FILE="$REPO_ROOT/harness/embed-server.pid"
LOG_FILE="$REPO_ROOT/harness/embed-server.log"

if ! have llama-server; then
    fail "llama-server not on PATH. Install via 'brew install llama.cpp'."
    exit 1
fi

if [[ ! -f "$EMBED_GGUF" ]]; then
    fail "GGUF not found: $EMBED_GGUF"
    fail "Download it via:"
    echo "    mkdir -p ~/llama-models && cd ~/llama-models &&"
    echo "    curl -L --fail -o Qwen3-Embedding-4B-Q8_0.gguf \\"
    echo "      https://huggingface.co/Qwen/Qwen3-Embedding-4B-GGUF/resolve/main/Qwen3-Embedding-4B-Q8_0.gguf"
    exit 1
fi

if listening "$EMBED_HOST" "$EMBED_PORT"; then
    ok "llama-server already listening on $EMBED_HOST:$EMBED_PORT"
    exit 0
fi

hdr "Starting llama-server (embeddings)"
kv "GGUF" "$EMBED_GGUF"
kv "bind" "$EMBED_HOST:$EMBED_PORT"
kv "log"  "$LOG_FILE"

# --embeddings turns on the /v1/embeddings endpoint AND switches the model
# context into pooled-embedding mode. --no-webui drops the chat UI we don't
# need. --ubatch-size and --batch-size kept default; M-series GPUs handle
# 2560-dim batched embeddings comfortably.
nohup llama-server \
    --model "$EMBED_GGUF" \
    --embeddings \
    --host "$EMBED_HOST" \
    --port "$EMBED_PORT" \
    --pooling last \
    --no-webui \
    >"$LOG_FILE" 2>&1 &

echo $! > "$PID_FILE"
sleep 0.5
pid=$(cat "$PID_FILE")
ok "llama-server pid=$pid"

# Wait for /v1/embeddings to respond.
booted=0
for i in $(seq 1 60); do
    if curl -fsS --max-time 1 "http://$EMBED_HOST:$EMBED_PORT/health" >/dev/null 2>&1; then
        ok "llama-server healthy on http://$EMBED_HOST:$EMBED_PORT (after ${i}s)"
        booted=1
        break
    fi
    sleep 1
done

if (( ! booted )); then
    fail "llama-server didn't come up. Tail the log:  tail -f $LOG_FILE"
    exit 1
fi
