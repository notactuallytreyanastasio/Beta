#!/usr/bin/env bash
# Diagnostics: report what the harness needs and what's actually present.
# No state is changed. Exits 0 unless something is unrecoverably wrong.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

hdr "Prerequisites"
for bin in docker just uv curl deciduous python3; do
    if have "$bin"; then ok "$bin       $(command -v "$bin")"
    else fail "$bin       (not on PATH)"
    fi
done

hdr "Sibling repos — integrated (harness reads from these)"
for entry in \
    "Alpha-dotclaude|$ALPHA_DOTCLAUDE|Pondsiders/Alpha-dotclaude" \
    "Alpha-System-Prompts|$ALPHA_SYSPROMPTS|jefferyharrell/Alpha-System-Prompts" \
    "agent-fleet|$AGENT_FLEET|Pondsiders/agent-fleet" \
    "Loom-dotclaude|$LOOM_DOTCLAUDE|Pondsiders/Loom-dotclaude"
do
    IFS='|' read -r name path remote <<< "$entry"
    if [[ -n "$path" ]]; then ok "$name   $path"
    else warn "$name   (not cloned — cd ../ && gh repo clone $remote)"
    fi
done

hdr "Sibling repos — reference (documentary, optional)"
for entry in \
    "Claude-Hooks|$CLAUDE_HOOKS|Pondsiders/Claude-Hooks" \
    "Intro|$INTRO_REPO|Pondsiders/Intro" \
    "Alpha-SDK|$ALPHA_SDK|Pondsiders/Alpha-SDK" \
    "House-SDK|$HOUSE_SDK|Pondsiders/House-SDK" \
    "pondside-sdk|$PONDSIDE_SDK|Pondsiders/pondside-sdk"
do
    IFS='|' read -r name path remote <<< "$entry"
    if [[ -n "$path" ]]; then ok "$name   $path"
    else warn "$name   (not cloned — cd ../ && gh repo clone $remote)"
    fi
done

hdr "Local .claude integration"
for p in agents/Alpha.md context/identity.md skills/start/SKILL.md settings.json; do
    if [[ -f "$REPO_ROOT/.claude/$p" ]]; then ok ".claude/$p"
    else fail ".claude/$p   (missing — re-run 'just harness-sync')"
    fi
done
if [[ -f "$REPO_ROOT/.mcp.json" ]]; then ok ".mcp.json"
else fail ".mcp.json   (missing — re-run 'just harness-sync')"
fi

hdr "Environment file (.env at repo root)"
if [[ -f "$REPO_ROOT/.env" ]]; then
    ok ".env present"
    required=(
        chat_api_key chat_base_url chat_model
        embedding_api_key embedding_base_url embedding_model
        database_url redis_url logfire_token timezone
    )
    missing=()
    for key in "${required[@]}"; do
        if grep -qiE "^[[:space:]]*${key}[[:space:]]*=" "$REPO_ROOT/.env"; then
            ok "  $key"
        else
            missing+=("$key")
        fi
    done
    if (( ${#missing[@]} )); then
        for k in "${missing[@]}"; do fail "  $k (missing from .env)"; done
        warn "alpha-server will fail to start without all required keys."
    fi
else
    warn ".env not present — alpha-server cannot start. (Substrate-only mode still works.)"
fi

hdr "Deciduous state (this checkout)"
if [[ -d "$REPO_ROOT/.deciduous" ]]; then
    node_count=$(cd "$REPO_ROOT" && deciduous nodes 2>/dev/null | grep -cE '^[0-9]+' || true)
    ok ".deciduous/ initialized — $node_count nodes"
else
    warn ".deciduous/ not initialized — first deciduous command will create it"
fi

hdr "Running services"
if have docker; then
    services=$(compose_up || true)
    if [[ -n "$services" ]]; then
        while read -r svc; do ok "compose service: $svc"; done <<<"$services"
    else
        warn "compose-dev.yml not up (try: just dev-up)"
    fi
fi
if listening 127.0.0.1 8000; then
    if livez_ok; then ok "alpha-server  http://127.0.0.1:8000/livez"
    else warn "port 8000 listening but /livez not OK"
    fi
else
    warn "alpha-server not listening on 127.0.0.1:8000 (try: just server-up)"
fi

echo
printf "%sdoctor done.%s  See 'just' for recipes.\n" "$DIM" "$RESET"
