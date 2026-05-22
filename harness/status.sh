#!/usr/bin/env bash
# One-screen status: are the layers up?
# Exits 0 always; this is read-only.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

hdr "Harness status"

# Layer 1 — config
if [[ -f "$REPO_ROOT/.claude/agents/Alpha.md" ]] \
   && [[ -f "$REPO_ROOT/.mcp.json" ]] \
   && grep -q '"agent": "Alpha"' "$REPO_ROOT/.claude/settings.json" 2>/dev/null; then
    ok "Alpha .claude/ config integrated (agent=Alpha, MCP wired)"
else
    fail "Alpha .claude/ config NOT fully integrated"
fi

# Layer 2 — deciduous
if [[ -d "$REPO_ROOT/.deciduous" ]]; then
    n_nodes=$(cd "$REPO_ROOT" && deciduous nodes 2>/dev/null | grep -cE '^[0-9]+' || echo 0)
    ok "deciduous graph     $n_nodes nodes"
else
    warn "deciduous not initialized"
fi

# Layer 3 — dev stack
if compose_up | grep -qx postgres; then ok "Postgres (compose)"
else warn "Postgres NOT running   (just dev-up)"
fi
if compose_up | grep -qx redis; then ok "Redis (compose)"
else warn "Redis NOT running      (just dev-up)"
fi

# Layer 4 — alpha-server
if listening 127.0.0.1 8000; then
    if livez_ok; then ok "alpha-server         http://127.0.0.1:8000/livez OK"
    else warn "alpha-server          port 8000 up but /livez not OK"
    fi
else
    warn "alpha-server NOT up    (just server-up)"
fi

# Layer 5 — system-prompts rendered?
rendered_dir="$REPO_ROOT/docs/system-prompts"
if [[ -f "$rendered_dir/claude_code.md" ]]; then
    age=$(stat -f '%Sm' -t '%Y-%m-%d %H:%M' "$rendered_dir/claude_code.md" 2>/dev/null || stat -c '%y' "$rendered_dir/claude_code.md")
    ok "system prompts rendered  $rendered_dir/claude_code.md ($age)"
else
    warn "system prompts not rendered  (just prompt-render)"
fi

# Layer 6 — agents inventory
n_agents=$(find "$REPO_ROOT/.claude/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if (( n_agents > 0 )); then
    ok "agents installed       $n_agents in .claude/agents/  ($(find "$REPO_ROOT/.claude/agents" -maxdepth 1 -name '*.md' -exec basename {} .md \; | tr '\n' ' '))"
fi
if [[ -d "$REPO_ROOT/.claude/alpha-hooks" ]]; then
    n_hk=$(find "$REPO_ROOT/.claude/alpha-hooks" -name '*.py' 2>/dev/null | wc -l | tr -d ' ')
    if (( n_hk > 0 )); then
        ok "Claude-Hooks mirror    $n_hk Python scripts in .claude/alpha-hooks/ (reference only)"
    fi
fi
