#!/usr/bin/env bash
# Render Alpha-System-Prompts templates into docs/system-prompts/.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if [[ -z "$ALPHA_SYSPROMPTS" ]]; then
    fail "Alpha-System-Prompts not cloned beside Alpha. Run:"
    echo "      cd $REPO_ROOT/.. && gh repo clone jefferyharrell/Alpha-System-Prompts"
    exit 1
fi

out_dir="$REPO_ROOT/docs/system-prompts"
mkdir -p "$out_dir"

hdr "Rendering from $ALPHA_SYSPROMPTS"

# render.py expects to run from the repo root because Jinja's FileSystemLoader
# is constructed with '.'. Run it there, redirect output here.
(
    cd "$ALPHA_SYSPROMPTS"
    if [[ ! -d ".venv" ]]; then
        warn ".venv not present in Alpha-System-Prompts; running 'uv sync' first"
        uv sync >/dev/null 2>&1
    fi

    for tpl in claude_code.j2 claude_desktop.j2; do
        out_name="${tpl%.j2}.md"
        if uv run python render.py "$tpl" "$out_dir/$out_name" >/dev/null; then
            bytes=$(wc -c <"$out_dir/$out_name" | tr -d ' ')
            ok "$out_dir/$out_name   (${bytes} bytes)"
        else
            fail "$tpl   (render failed)"
        fi
    done
)
