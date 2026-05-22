#!/usr/bin/env bash
# Pull the latest .claude/ payload from sibling Alpha-dotclaude into THIS checkout.
# Preserves deciduous's commands/, hooks/, skills/* — only Alpha-owned subtrees
# (agents/, context/, rules/, skills/start/) are overwritten.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ -z "$ALPHA_DOTCLAUDE" ]]; then
    fail "Alpha-dotclaude not cloned beside Alpha. Run:"
    echo "      cd $REPO_ROOT/.. && gh repo clone Pondsiders/Alpha-dotclaude"
    exit 1
fi

hdr "Syncing .claude/ from $ALPHA_DOTCLAUDE"

mkdir -p "$REPO_ROOT/.claude/agents" \
         "$REPO_ROOT/.claude/context" \
         "$REPO_ROOT/.claude/rules" \
         "$REPO_ROOT/.claude/skills/start"

# Alpha-owned subtrees: faithful mirror from Alpha-dotclaude.
for src in \
    "agents/Alpha.md" \
    "agents/Answertron.md" \
    "agents/Librarian.md" \
    "context/identity.md" \
    "context/household.md" \
    "context/lexicon.md" \
    "rules/python.md" \
    "rules/workshop.md" \
    "skills/start/SKILL.md"
do
    if [[ -f "$ALPHA_DOTCLAUDE/$src" ]]; then
        install -m 0644 "$ALPHA_DOTCLAUDE/$src" "$REPO_ROOT/.claude/$src"
        ok "$src"
    else
        warn "$src   (not present in Alpha-dotclaude — skipped)"
    fi
done

# .mcp.json at repo root.
if [[ -f "$ALPHA_DOTCLAUDE/.mcp.json" ]]; then
    install -m 0644 "$ALPHA_DOTCLAUDE/.mcp.json" "$REPO_ROOT/.mcp.json"
    ok ".mcp.json   (repo root)"
fi

# agent-fleet specialists: Edgar, Lazlo, Mac, Operator.
if [[ -n "$AGENT_FLEET" ]]; then
    hdr "Pulling agent-fleet plugins"
    for name in edgar lazlo mac operator; do
        cap="$(tr '[:lower:]' '[:upper:]' <<<"${name:0:1}")${name:1}"
        src_file="$AGENT_FLEET/$name/agents/$cap.md"
        if [[ -f "$src_file" ]]; then
            install -m 0644 "$src_file" "$REPO_ROOT/.claude/agents/$cap.md"
            ok "agents/$cap.md"
        else
            warn "agents/$cap.md   (not present — skipped)"
        fi
    done
else
    warn "agent-fleet not cloned — skipping Edgar/Lazlo/Mac/Operator"
fi

# Loom-dotclaude extras: Programmer + Researcher (Librarian skipped — Alpha-dotclaude's wins).
if [[ -n "$LOOM_DOTCLAUDE" ]]; then
    hdr "Pulling Loom-dotclaude extras"
    for name in Programmer Researcher; do
        src_file="$LOOM_DOTCLAUDE/agents/$name.md"
        if [[ -f "$src_file" ]]; then
            install -m 0644 "$src_file" "$REPO_ROOT/.claude/agents/$name.md"
            ok "agents/$name.md"
        else
            warn "agents/$name.md   (not present in Loom-dotclaude — skipped)"
        fi
    done
fi

# Claude-Hooks: alternative Python hooks pipeline. Read-only mirror to .claude/alpha-hooks/.
# These are NOT wired into settings.json — they require Intro/Loom/Deliverator infrastructure.
if [[ -n "$CLAUDE_HOOKS" ]]; then
    hdr "Mirroring Claude-Hooks (read-only; see harness/manifest.md)"
    mkdir -p "$REPO_ROOT/.claude/alpha-hooks"
    for script in session_start.py user_prompt_submit.py stop.py; do
        if [[ -f "$CLAUDE_HOOKS/$script" ]]; then
            install -m 0755 "$CLAUDE_HOOKS/$script" "$REPO_ROOT/.claude/alpha-hooks/$script"
            ok "alpha-hooks/$script"
        fi
    done
fi

hdr "Merging settings.json"
# We intentionally do NOT overwrite settings.json — the merged version carries
# both Alpha's hooks (UserPromptSubmit, Stop) and deciduous's hooks
# (PreToolUse, PostToolUse). Verify the merge is still in place; warn if not.
sj="$REPO_ROOT/.claude/settings.json"
if [[ ! -f "$sj" ]]; then
    fail ".claude/settings.json missing — restore from version control"
    exit 1
fi
have=0; missing=()
for needle in '"agent": "Alpha"' '"UserPromptSubmit"' '"Stop"' '"PreToolUse"' '"PostToolUse"'; do
    if grep -q "$needle" "$sj"; then
        have=$((have+1))
    else
        missing+=("$needle")
    fi
done
if (( have == 5 )); then
    ok "settings.json carries all five expected sections"
else
    warn "settings.json is missing: ${missing[*]}"
    warn "(open .claude/settings.json and reconcile against harness/README.md)"
fi
