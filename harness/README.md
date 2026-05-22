# harness/

A small set of shell scripts that bring up Beta + deciduous side by side from one checkout. Each recipe is exposed in the repo-root `justfile` (`just harness-doctor`, `just harness-up`, `just harness-status`, etc.).

## What the harness composes

```
┌──────────────────────────────────────────────────────────────────────┐
│ One Claude Code session in this directory ─────────────────────────┐ │
│                                                                    │ │
│  reads .claude/agents/Beta.md          ◄── persona                │ │
│  reads .claude/context/*.md             ◄── identity, household    │ │
│  loads .mcp.json → cortex, utils MCP    ◄── memory + fetch tools   │ │
│  posts UserPromptSubmit → /hooks/timestamp + /hooks/memories       │ │
│  posts Stop → /hooks/reflection                                    │ │
│  posts PreToolUse (Edit|Write|Bash) → deciduous policy scripts     │ │
│                                                                    │ │
└───┬────────────────────────────────────────────────────────────────┘ │
    │                                                                  │
    │ http://localhost:8000                                            │
    ▼                                                                  │
┌──────────────────────────────┐                                       │
│ alpha-server (uvicorn)       │                                       │
│   /cortex/mcp, /utils/mcp    │                                       │
│   /hooks/{timestamp,         │                                       │
│           memories,          │                                       │
│           reflection}        │                                       │
└──┬─────────────────┬─────────┘                                       │
   │                 │                                                 │
   ▼                 ▼                                                 │
┌──────────┐   ┌──────────┐         ┌─────────────────────────────┐    │
│ Postgres │   │  Redis   │         │  .deciduous/  (this repo)   │    │
│ (Cortex) │   │ (session │         │  decision graph DB           │◄───┘
│          │   │  state)  │         │  64+ nodes documenting the   │
└──────────┘   └──────────┘         │  design history              │
                                    └─────────────────────────────┘

dev stack: docker compose -f compose-dev.yml
```

The harness's job is to make sure every box is up and to fail informatively when something can't be.

## Recipes

| `just` recipe    | What it does                                                                                                                                                                                                                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `harness-doctor` | Pre-flight check. Reports prerequisites (`docker`, `uv`, `just`, `deciduous`, `curl`), sibling repo presence, local `.claude/` integration state, `.env` keys, deciduous DB, and any running services. Read-only.                                                                                  |
| `harness-status` | One-screen "is it up?" — five layers: config / deciduous / dev stack / alpha-server / rendered prompts. Read-only.                                                                                                                                                                                 |
| `harness-up`     | Idempotent startup. Bring up dev stack → optionally start alpha-server (if `.env` is complete) → render system prompts (if Beta-System-Prompts is present) → status.                                                                                                                               |
| `harness-down`   | Graceful teardown. Stops alpha-server (PID file), then dev stack. Data volumes preserved.                                                                                                                                                                                                          |
| `harness-sync`   | Pull the latest Beta-owned `.claude/` payload (agents, context, rules, start skill, `.mcp.json`) from the sibling `../Beta-dotclaude` checkout into here. Preserves deciduous's `commands/`, `hooks/`, `skills/`. Reports if `settings.json`'s merge is missing any of the five expected sections. |
| `server-up`      | Start just alpha-server in the background (assumes dev stack already up). PID in `harness/alpha-server.pid`.                                                                                                                                                                                       |
| `prompt-render`  | Run `Beta-System-Prompts/render.py` to produce `docs/system-prompts/claude_code.md` and `claude_desktop.md`.                                                                                                                                                                                       |

## Sibling-repo expectations

The harness assumes both companion repos are cloned beside `Beta/`:

```
~/code/
├── Beta/                       # this repo (alpha-server)
├── Beta-dotclaude/             # github.com/Pondsiders/Beta-dotclaude
└── Beta-System-Prompts/        # github.com/jefferyharrell/Beta-System-Prompts
```

If they aren't present, `harness-doctor` says so and `harness-sync` / `prompt-render` will refuse to run (with the `gh repo clone` command to fix it).

## Degraded modes

- **No `.env`**: `harness-up` brings the dev stack up but skips alpha-server. Cortex/Utils tools and hook URLs return 404. Useful for working on `.claude/` config without needing the full backend.
- **`.env` incomplete**: same as above. `harness-doctor` lists exactly which keys are missing.
- **No `Beta-System-Prompts/`**: prompt rendering is skipped. The live persona doctrine is in `.claude/agents/Beta.md` regardless — the Beta-System-Prompts repo is the legacy layer.
- **No `Beta-dotclaude/`**: `harness-sync` is unavailable. The integrated `.claude/` already in this checkout still works; you just can't pull updates.

## Layer-by-layer description

### Layer 1 — `.claude/` (integrated)

Already in this checkout (committed by `harness-sync`):

```
.claude/
├── agents/      Beta.md, Answertron.md, Librarian.md        ◄ from Beta-dotclaude
├── context/     identity.md, household.md, lexicon.md        ◄ from Beta-dotclaude
├── rules/       python.md, workshop.md (path-scoped)         ◄ from Beta-dotclaude
├── skills/start/SKILL.md                                      ◄ from Beta-dotclaude
├── commands/    decision.md, work.md, recover.md, etc.       ◄ deciduous template
├── hooks/       require-action-node.sh, etc.                 ◄ deciduous template
├── skills/      archaeology.md, narratives.md, pulse.md      ◄ deciduous template
└── settings.json                                              ◄ MERGED — see below
.mcp.json                                                      ◄ from Beta-dotclaude
```

The merged `settings.json` carries five hook sections that don't overlap:

| Event                      | Endpoint                                 | Layer     |
| -------------------------- | ---------------------------------------- | --------- |
| `UserPromptSubmit`         | `http://localhost:8000/hooks/timestamp`  | Beta      |
| `UserPromptSubmit`         | `http://localhost:8000/hooks/memories`   | Beta      |
| `Stop`                     | `http://localhost:8000/hooks/reflection` | Beta      |
| `PreToolUse` (Edit\|Write) | `.claude/hooks/require-action-node.sh`   | deciduous |
| `PreToolUse` (Bash)        | `.claude/hooks/version-check.sh`         | deciduous |
| `PostToolUse` (Bash)       | `.claude/hooks/post-commit-reminder.sh`  | deciduous |

### Layer 2 — deciduous

The `.deciduous/` directory in this repo holds the decision-graph DB. Created on first `deciduous` call. `harness-doctor` reports node count.

### Layer 3 — dev stack

`compose-dev.yml` at the repo root brings up `pgvector/pgvector:pg17` on 5432 and `redis:8-alpine` on 6379. Volumes `alpha-dev-pgdata` and `alpha-dev-redis` persist across restarts.

### Layer 4 — alpha-server

`uv run uvicorn alpha_server.app:app --host 127.0.0.1 --port 8000` from inside `alpha-server/`. The harness backgrounds it and writes the PID to `harness/alpha-server.pid` for clean shutdown.

### Layer 5 — system prompts (rendered)

`Beta-System-Prompts/render.py` reads the input templates and emits `claude_code.md` / `claude_desktop.md` into `docs/system-prompts/`. These are reference artifacts (legacy persona layer); the live persona is in `.claude/agents/Beta.md`.

## Why this is a harness and not a server

The name follows Beta's own usage. From `agents/Beta.md`:

> **Workshop** is where you run today. It's a VM on Primer that hosts Claude Code (your harness) and alpha-server (the Docker container with your MCP tools and hooks). [...] If Workshop gets trashed — by an experiment, by a mistake, by anything — the fix is _spin up a replacement VM and clone the repo again._ You lose no data. Workshop is the disposable surface.

The harness is the disposable surface: the stuff that brings up the runtime around the model. Workshop in the wild; this directory on your laptop.
