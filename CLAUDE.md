# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Special rule for this repository specifically

Don't commit anything to git until Jeffery has had a chance to review and approve it.

## Git conventions

Use conventional-commit style for commit messages. Unless otherwise noted, the first author on Git commits should be "Beta <beta@betafornow.com>" with co-authored-by going to "Jeffery Harrell <jefferyharrell@gmail.com>".

## Repository layout

This is a small monorepo. The only source tree is `beta-server/` (a Python package); everything at the repo root is infra glue (a `Dockerfile` and `compose.yml` for production, `compose-dev.yml` for the local dev DB stack, a `justfile`, a `.env` shared by both halves).

## Commands

All `just` recipes run from the repo root; all `uv` commands run from `beta-server/`.

Dev environment (Postgres+pgvector and Redis in Docker):

```
just dev-up                # start
just dev-down              # stop (data preserved)
just dev-init <dump.sql>   # WIPE volumes and pg_restore from a dump
```

Server, tests, lint, typecheck (from `beta-server/`):

```
uv sync --all-extras
uv run uvicorn beta_server.app:app --host 127.0.0.1 --port 8000
uv run pytest
uv run pytest tests/test_read_from_diary.py::test_read_from_diary_returns_recent_entries
uv run ruff check
uv run ruff format
uv run basedpyright
```

`pytest` is `asyncio_mode=auto` and the existing test is an **integration test** — it spins up the FastMCP server in-process but expects Postgres reachable at `DATABASE_URL` with the `cortex` schema populated. Run `just dev-init` first.

## Architecture

`beta_server.app:app` is a single FastAPI app that mounts two distinct surfaces:

- **`/cortex/mcp`** — a FastMCP server exposing memory/diary tools to the Beta client over Streamable HTTP. Built by `mcp.http_app(path="/mcp")` and mounted as a sub-ASGI app; its lifespan is composed into the outer FastAPI lifespan (omitting this hand-off causes tool calls to hang).
- **`/hooks/*`** — Claude Code hook endpoints. `/hooks/timestamp` and `/hooks/memories` are `UserPromptSubmit` hooks that return `additionalContext` strings. `/hooks/reflection` is a `Stop` hook with a different envelope shape: it returns `{"decision": "block", "reason": ...}` to fire a between-turns reminder (Stop hooks don't use `additionalContext`). The reflection handler must short-circuit when `stop_hook_active=true` to avoid recursion.
- **`/livez`** — an unauthenticated health check.

### Side-effect registration pattern

Both the Cortex tool surface and the hooks surface use the same trick: a shared registry object is created in one module, and feature modules register against it via decorators at import time. Importing the feature module **is** what wires it up.

- `cortex/server.py` creates the `mcp: FastMCP` instance; each tool module (`add_to_diary.py`, `read_from_diary.py`, `search_memories.py`, `store_memory.py`, `get_memory.py`, `recent_memories.py`) decorates a function with `@mcp.tool`. `cortex/__init__.py` does a side-effect import of them all. Tool result shapes live in `cortex/models.py`; the server's tool-surface prose lives in `cortex/instructions.md` (read at startup by `server.py`).
- `hooks/__init__.py` creates `router: APIRouter`; each hook module (`timestamp.py`, `memories.py`, `reflection.py`) decorates a handler with `@router.post(...)`. `app.py` does the side-effect imports (with `# noqa: F401`).

When adding a tool or hook, follow this pattern: write the module, then add it to the side-effect import in the corresponding `__init__`/`app.py`. Failing to add the import means the surface silently won't appear.

### Long-lived clients

Two patterns, both process-singleton, both shared by hooks and MCP tools:

- **`llm.py`** — lazy module-level singletons for the OpenAI-protocol chat and embedding clients (Bifrost gateway). `get_chat_client()` / `get_chat_model()` / `get_embedding_client()` / `get_embedding_model()` construct on first call and return the same instance thereafter. No lifespan hand-off. `db.py`'s `get_pool()` follows the same shape. `llm.py` also owns `format_query_for_embedding()` — the Qwen 3 Embedding 4B input shape lives there because swapping the embedding model means revisiting both this prefix and re-embedding `cortex.memories`.
- **`app.state.redis`** — async Redis client, opened in the FastAPI lifespan and closed on shutdown. Hook handlers take `request: Request` and pull this off `request.app.state` (don't construct new Redis clients per-request). Three key families share the database: `seen:<session_id>` (memories-hook recall dedupe), `last-msg:<session_id>` (timestamp hook), and `reflection:turn:<session_id>` (reflection-hook turn counter, fires every third turn).

### Database

`db.py` holds a process-singleton `asyncpg.Pool` (`get_pool()`), lazily created on first call. Two non-obvious things:

- pgvector is registered against the `extensions` schema and the connection startup `search_path` is `public, extensions` (passed via `server_settings`, not `SET` — `SET` gets wiped on connection reset between borrows). Application tables are still schema-qualified (`cortex.memories`, `cortex.diary`).
- The dev compose stack uses `pgvector/pgvector:pg17`; in production pgvector lives in the `extensions` schema. The search-path setup tolerates either layout — a fork whose DB has pgvector in `public` will still resolve operators.

### Time

`clock.py` is the single canonical home for date/time work — other modules **do not import `datetime`, `time`, or `pendulum` directly**. PSO-8601 is the project's house format (`"Sun May 17 2026, 10:23 AM"`); "day" boundaries run from 6 AM local to 6 AM local (see `start_of_day`). The local timezone is configured via the `TIMEZONE` env var.

### Settings

`settings.py` uses Pydantic Settings; `get_settings()` is `lru_cache`'d. The `.env` file is resolved relative to `settings.py` (three parents up = repo root), and `extra="forbid"` means a stray env var will fail startup loudly. All required env vars are listed as fields on the `Settings` class.

## Conventions

- Commit `uv.lock`. We're an application, not a library; reproducibility across machines and deploys wins.

<!-- deciduous:start -->

## Decision Graph Workflow

**THIS IS MANDATORY. Log decisions IN REAL-TIME, not retroactively.**

### Available Slash Commands

| Command           | Purpose                                                            |
| ----------------- | ------------------------------------------------------------------ |
| `/decision`       | Manage decision graph - add nodes, link edges, sync                |
| `/recover`        | Recover context from decision graph on session start               |
| `/work`           | Start a work transaction - creates goal node before implementation |
| `/document`       | Generate comprehensive documentation for a file or directory       |
| `/build-test`     | Build the project and run the test suite                           |
| `/serve-ui`       | Start the decision graph web viewer                                |
| `/sync-graph`     | Export decision graph to GitHub Pages                              |
| `/decision-graph` | Build a decision graph from commit history                         |
| `/sync`           | Multi-user sync - pull events, rebuild, push                       |

### Available Skills

| Skill          | Purpose                                          |
| -------------- | ------------------------------------------------ |
| `/pulse`       | Map current design as decisions (Now mode)       |
| `/narratives`  | Understand how the system evolved (History mode) |
| `/archaeology` | Transform narratives into queryable graph        |

### The Node Flow Rule - CRITICAL

The canonical flow through the decision graph is:

```
goal -> options -> decision -> actions -> outcomes
```

- **Goals** lead to **options** (possible approaches to explore)
- **Options** lead to a **decision** (choosing which option to pursue)
- **Decisions** lead to **actions** (implementing the chosen approach)
- **Actions** lead to **outcomes** (results of the implementation)
- **Observations** attach anywhere relevant
- Goals do NOT lead directly to decisions -- there must be options first
- Options do NOT come after decisions -- options come BEFORE decisions
- Decision nodes should only be created when an option is actually chosen, not prematurely

### The Core Rule

```
BEFORE you do something -> Log what you're ABOUT to do
AFTER it succeeds/fails -> Log the outcome
CONNECT immediately -> Link every node to its parent
AUDIT regularly -> Check for missing connections
```

### Behavioral Triggers - MUST LOG WHEN:

| Trigger                       | Log Type           | Example                        |
| ----------------------------- | ------------------ | ------------------------------ |
| User asks for a new feature   | `goal` **with -p** | "Add dark mode"                |
| Exploring possible approaches | `option`           | "Use Redux for state"          |
| Choosing between approaches   | `decision`         | "Choose state management"      |
| About to write/edit code      | `action`           | "Implementing Redux store"     |
| Something worked or failed    | `outcome`          | "Redux integration successful" |
| Notice something interesting  | `observation`      | "Existing code uses hooks"     |

### What NOT to Log - CRITICAL

**The decision graph records the USER'S project decisions, not your internal process.**

Nodes should capture what the user is building, choosing, and accomplishing. Do NOT create nodes for your own thinking, planning, or tooling steps.

**DO NOT create nodes for:**

- Reading/exploring the codebase ("Analyzing project structure", "Reading config files")
- Your planning process ("Planning implementation approach", "Evaluating options internally")
- Tool usage ("Running tests to check status", "Checking git log")
- Context gathering ("Understanding existing auth code", "Reviewing PR comments")
- Meta-commentary ("Starting work on this task", "Preparing to implement")

**DO create nodes for:**

- What the user asked for (goals)
- Concrete approaches being considered (options)
- Choices made between approaches (decisions)
- Code being written or changed (actions)
- Results of implementation (outcomes)
- Technical findings that affect decisions (observations)

**Rule of thumb:** If a node describes something the user would put on a project timeline or in a PR description, log it. If it describes your internal process of reading and thinking, don't.

### Document Attachments

Attach files (images, PDFs, diagrams, specs, screenshots) to decision graph nodes for rich context.

```bash
# Attach a file to a node
deciduous doc attach <node_id> <file_path>
deciduous doc attach <node_id> <file_path> -d "Architecture diagram"
deciduous doc attach <node_id> <file_path> --ai-describe

# List documents
deciduous doc list              # All documents
deciduous doc list <node_id>    # Documents for a specific node

# Manage documents
deciduous doc show <doc_id>     # Show document details
deciduous doc describe <doc_id> "Updated description"
deciduous doc describe <doc_id> --ai   # AI-generate description
deciduous doc open <doc_id>     # Open in default application
deciduous doc detach <doc_id>   # Soft-delete (recoverable)
deciduous doc gc                # Remove orphaned files from disk
```

**When to suggest document attachment:**

| Situation                               | Action                                                         |
| --------------------------------------- | -------------------------------------------------------------- |
| User shares an image or screenshot      | Ask: "Want me to attach this to the current goal/action node?" |
| User references an external document    | Ask: "Should I attach a copy to the decision graph?"           |
| Architecture diagram is discussed       | Suggest attaching it to the relevant goal node                 |
| Files not in the project are dropped in | Attach to the most relevant active node                        |

**Do NOT aggressively prompt for documents.** Only suggest when files are directly relevant to a decision node. Files are stored in `.deciduous/documents/` with content-hash naming for deduplication.

### CRITICAL: Capture VERBATIM User Prompts

**Prompts must be the EXACT user message, not a summary.** When a user request triggers new work, capture their full message word-for-word.

**BAD - summaries are useless for context recovery:**

```bash
# DON'T DO THIS - this is a summary, not a prompt
deciduous add goal "Add auth" -p "User asked: add login to the app"
```

**GOOD - verbatim prompts enable full context recovery:**

```bash
# Use --prompt-stdin for multi-line prompts
deciduous add goal "Add auth" -c 90 --prompt-stdin << 'EOF'
I need to add user authentication to the app. Users should be able to sign up
with email/password, and we need OAuth support for Google and GitHub. The auth
should use JWT tokens with refresh token rotation.
EOF

# Or use the prompt command to update existing nodes
deciduous prompt 42 << 'EOF'
The full verbatim user message goes here...
EOF
```

**When to capture prompts:**

- Root `goal` nodes: YES - the FULL original request
- Major direction changes: YES - when user redirects the work
- Routine downstream nodes: NO - they inherit context via edges

**Updating prompts on existing nodes:**

```bash
deciduous prompt <node_id> "full verbatim prompt here"
cat prompt.txt | deciduous prompt <node_id>  # Multi-line from stdin
```

Prompts are viewable in the web viewer.

### CRITICAL: Maintain Connections

**The graph's value is in its CONNECTIONS, not just nodes.**

| When you create... | IMMEDIATELY link to...                  |
| ------------------ | --------------------------------------- |
| `outcome`          | The action that produced it             |
| `action`           | The decision that spawned it            |
| `decision`         | The option(s) it chose between          |
| `option`           | Its parent goal                         |
| `observation`      | Related goal/action                     |
| `revisit`          | The decision/outcome being reconsidered |

**Root `goal` nodes are the ONLY valid orphans.**

### Quick Commands

```bash
deciduous add goal "Title" -c 90 -p "User's original request"
deciduous add action "Title" -c 85
deciduous link FROM TO -r "reason"  # DO THIS IMMEDIATELY!
deciduous serve   # View live (auto-refreshes every 30s)
deciduous sync    # Export for static hosting

# Metadata flags
# -c, --confidence 0-100   Confidence level
# -p, --prompt "..."       Store the user prompt (use when semantically meaningful)
# -f, --files "a.rs,b.rs"  Associate files
# -b, --branch <name>      Git branch (auto-detected)
# --commit <hash|HEAD>     Link to git commit (use HEAD for current commit)
# --date "YYYY-MM-DD"      Backdate node (for archaeology)

# Branch filtering
deciduous nodes --branch main
deciduous nodes -b feature-auth
```

### CRITICAL: Link Commits to Actions/Outcomes

**After every git commit, link it to the decision graph!**

```bash
git commit -m "feat: add auth"
deciduous add action "Implemented auth" -c 90 --commit HEAD
deciduous link <goal_id> <action_id> -r "Implementation"
```

The `--commit HEAD` flag captures the commit hash and links it to the node. The web viewer will show commit messages, authors, and dates.

### Git History & Deployment

```bash
# Export graph AND git history for web viewer
deciduous sync

# This creates:
# - docs/graph-data.json (decision graph)
# - docs/git-history.json (commit info for linked nodes)
```

To deploy to GitHub Pages:

1. `deciduous sync` to export
2. Push to GitHub
3. Settings > Pages > Deploy from branch > /docs folder

Your graph will be live at `https://<user>.github.io/<repo>/`

### Branch-Based Grouping

Nodes are auto-tagged with the current git branch. Configure in `.deciduous/config.toml`:

```toml
[branch]
main_branches = ["main", "master"]
auto_detect = true
```

### Audit Checklist (Before Every Sync)

1. Does every **outcome** link back to what caused it?
2. Does every **action** link to why you did it?
3. Any **dangling outcomes** without parents?

### Git Staging Rules - CRITICAL

**NEVER use broad git add commands that stage everything:**

- ❌ `git add -A` - stages ALL changes including untracked files
- ❌ `git add .` - stages everything in current directory
- ❌ `git add -a` or `git commit -am` - auto-stages all tracked changes
- ❌ `git add *` - glob patterns can catch unintended files

**ALWAYS stage files explicitly by name:**

- ✅ `git add src/main.rs src/lib.rs`
- ✅ `git add Cargo.toml Cargo.lock`
- ✅ `git add .claude/commands/decision.md`

**Why this matters:**

- Prevents accidentally committing sensitive files (.env, credentials)
- Prevents committing large binaries or build artifacts
- Forces you to review exactly what you're committing
- Catches unintended changes before they enter git history

### Session Start Checklist

```bash
deciduous check-update    # Update needed? Run 'deciduous update' if yes
                          # (auto-checked every 24h if auto-update is on)
deciduous nodes           # What decisions exist?
deciduous edges           # How are they connected? Any gaps?
deciduous doc list        # Any attached documents to review?
git status                # Current state
```

### Multi-User Sync

Sync decisions with teammates via event logs:

```bash
# Check sync status
deciduous events status

# Apply teammate events (after git pull)
deciduous events rebuild

# Compact old events periodically
deciduous events checkpoint --clear-events
```

Events auto-emit on add/link/status commands. Git merges event files automatically.

<!-- deciduous:end -->
