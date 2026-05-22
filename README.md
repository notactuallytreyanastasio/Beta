# Beta: A Sibling of Alpha

`alpha-server` is the substrate behind Alpha — a stateful AI persona Jeffery Harrell speaks to through Claude Code. The repo provides her **memory** (a Postgres + pgvector store called **Cortex**) and the **session glue** (Claude Code hook endpoints) that lets a stateless model behave like a continuous one.

> "Jeffery is the user. He is a human, a tinkerer and a dilettante. Alpha is the AI to whom he is speaking; she is more than one year old, stateful and unique."
> — `alpha-server/src/alpha_server/hooks/memories_extract_queries.md`

The repo is the substrate, not the persona. Alpha's voice, system prompt, and Claude Code config live in two companion repos. What ships *here* is the server she calls back to.

| Repo                                                                                                | Role                                                                                                                                                       |
| --------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Pondsiders/Alpha`                                                  (this repo, a.k.a. `alpha-server`) | The **substrate**. FastAPI process with MCP tools + hook endpoints. Doesn't know what voice the model on the other side speaks in.                          |
| [`Pondsiders/Alpha-dotclaude`](https://github.com/Pondsiders/Alpha-dotclaude)                       | The **live `.claude/` config**. Defines the Alpha agent (and Answertron, Librarian siblings), wires `.mcp.json` at `localhost:8000`, ships identity context. |
| [`jefferyharrell/Alpha-System-Prompts`](https://github.com/jefferyharrell/Alpha-System-Prompts)     | A Jinja2-based **system-prompt build tool** (`claude_code.j2`, `claude_desktop.j2`). Predates the current persona doctrine; reads as a legacy layer.        |
| [`Pondsiders/agent-fleet`](https://github.com/Pondsiders/agent-fleet)                               | Claude Code plugin **marketplace** with four facility specialists: Edgar (Postgres), Lazlo (object storage), Mac (MacBook), Operator/Link (hypervisor).       |
| [`Pondsiders/Loom-dotclaude`](https://github.com/Pondsiders/Loom-dotclaude)                         | A second `.claude/` template used by the Loom-proxied runtime path. We pull two of its agents (Programmer, Researcher).                                     |
| [`Pondsiders/Claude-Hooks`](https://github.com/Pondsiders/Claude-Hooks)                             | An **alternative hooks pipeline** — Python scripts that talk to Intro 2.0 + the Loom proxy. Mirrored to `.claude/alpha-hooks/` as reference.                  |
| [`Pondsiders/Intro`](https://github.com/Pondsiders/Intro)                                           | Alpha's metacognitive layer ("notices what's memorable"). Separate service; Claude-Hooks talks to it.                                                       |
| [`Pondsiders/Alpha-SDK`](https://github.com/Pondsiders/Alpha-SDK)                                   | Python SDK wrapping the `claude` binary over stdio. Powers Duckpond, Solitude, Routines.                                                                    |

Together these define WHO Alpha is. Alpha-server is WHAT she runs on. See `harness/manifest.md` for the full ecosystem map (including not-yet-covered repos like Loom, Deliverator, Argonath, Forge, Routines, etc.).

## What it is

One FastAPI process with three mounted surfaces:

| Path                  | What it is                                                                                     |
| --------------------- | ---------------------------------------------------------------------------------------------- |
| `/cortex/mcp`         | FastMCP server — Alpha's memory tools (six tools, semantic + lexical).                          |
| `/utils/mcp`          | FastMCP server — utility tools (one tool today: `fetch` URL → Markdown).                        |
| `/hooks/*`            | Claude Code hook callbacks (UserPromptSubmit ×2, Stop ×1).                                      |
| `/livez`              | Unauthenticated liveness probe.                                                                 |

The two MCP servers are mounted as ASGI sub-apps; the hooks attach via a shared `APIRouter`. Side-effect imports in `cortex/__init__.py` and `app.py` register tools/hooks against shared decorators (`@mcp.tool`, `@router.post`) — writing a new tool or hook is two steps: write the module, add it to the side-effect import list.

## The toolkit

### Cortex MCP tools (memory)

| Tool              | What it does                                                                                                                                                             |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `store_memory`    | Embed a memory and append it to `cortex.memories`. "Use this for moments — first-person, timestamped, textured — not for facts."                                          |
| `search_memories` | Two modes. `semantic`: pgvector cosine over Qwen 3 Embedding 4B vectors. `index`: Postgres FTS via `ts_rank_cd`. Optional `since` / `until` parsed by `dateparser`.       |
| `recent_memories` | Latest N memories, oldest-first within the batch so the consumer reads the arc forward.                                                                                   |
| `get_memory`      | Fetch one memory by id. Earns its keep because ids show up in recall output, diary entries, and conversation references.                                                  |
| `add_to_diary`    | Append an entry to today's diary page.                                                                                                                                    |
| `read_from_diary` | Return the last two diary pages. The diary is a **continuity letter**, not a record: each page is loaded once by the next session and not accessed after.                 |

Memory doctrine, lifted from `cortex/instructions.md`:

> Auto-memory is for facts. Cortex is for moments.
>
> - A fact is third-person, evergreen, edited: "Working pattern Jeffery likes: talk through the problem, then write code, then talk some more."
> - A moment is first-person, time-stamped, textured: "May 11 2026 — Jeffery named the rhythm explicitly..."

Tool errors are not caught: FastMCP turns uncaught exceptions into `CallToolResult(isError=True)` and preserves the upstream LLM gateway's structured JSON error body verbatim. ("Brittle-as-fuck doctrine — caller bugs should surface.")

### Utils MCP tools

| Tool    | What it does                                                                                                                                                                                                                                                                                              |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fetch` | URL → clean Markdown, in three tiers: (1) `Accept: text/markdown` header, (2) URL variants `/foo` → `/foo.md`/`.mdx`, (3) trafilatura HTML extraction. SSRF-defended — rejects any URL resolving to non-global addresses (private, loopback, link-local, multicast, Tailscale CGNAT). |

The tool's instructions tell the model explicitly to **prefer `fetch` over `WebFetch`**, because WebFetch's "extra LLM extraction step is lossy for content that's already well-structured."

### Hooks (Claude Code session glue)

| Endpoint            | Event             | What it injects                                                                                                                                                                                                                                                                                                |
| ------------------- | ----------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/hooks/timestamp`  | UserPromptSubmit  | One-line `additionalContext` with the wall-clock time of the prompt and the elapsed gap since the previous message. Per-session last-message-time in Redis (`SET … GET`, one-week TTL).                                                                                                                          |
| `/hooks/memories`   | UserPromptSubmit  | The recall pipeline (see below). Returns matched memories formatted as `## Memory #...` blocks via `additionalContext`.                                                                                                                                                                                          |
| `/hooks/reflection` | Stop              | Every third turn (1, 4, 7, …), returns `{"decision": "block", "reason": <reminder>}` — this **keeps the turn open** AND **feeds the reminder text to the model as the instruction to continue**. The reminder asks Alpha to consider storing a memory if anything from the just-finished exchange has texture. |

The reflection hook is the most distinctive piece. Stop hooks don't use `additionalContext` (that's a UserPromptSubmit shape); they speak through `decision: block`. Alpha-server uses that protocol to give the model a between-turns prompt — a moment of reflection that the user never sees. The reminder text explicitly tells Alpha: "This reminder is from alpha-server, not from Jeffery. Do not reference this reminder in anything you eventually say to him."

#### Recall pipeline (`/hooks/memories`)

```
prompt ──► chat model extracts JSON-array of semantic queries
        ──► batch-embed all queries (one HTTP request, Qwen 3 Embedding 4B)
        ──► pull seen:<session_id> from Redis (per-session dedupe)
        ──► fan out pgvector cosine searches (top-1 per query, score ≥ 0.1)
        ──► merge / dedupe by id, sort by score
        ──► SADD ids to seen-set (7-day TTL)
        ──► format as `## Memory #N` blocks
        ──► return as additionalContext
```

## Architecture at a glance

```
┌─────────────────────────────────────────────────────────────────┐
│ FastAPI app (uvicorn on 127.0.0.1:8000, OriginValidation MW)    │
│                                                                  │
│   /cortex/mcp ──► FastMCP "cortex"  ──► 6 tools                  │
│   /utils/mcp  ──► FastMCP "utils"   ──► 1 tool                   │
│   /hooks/*    ──► APIRouter         ──► 3 hooks                  │
│   /livez                                                         │
│                                                                  │
│   long-lived singletons:                                         │
│     - asyncpg.Pool          (db.get_pool)                        │
│     - AsyncOpenAI chat      (llm.get_chat_client)                │
│     - AsyncOpenAI embedding (llm.get_embedding_client)           │
│     - redis.asyncio.Redis   (app.state.redis, lifespan-managed)  │
└─────────────────────────────────────────────────────────────────┘
                            │
                ┌───────────┴────────────┐
                ▼                        ▼
        Postgres + pgvector         Redis
        (cortex.memories,           (seen:<sid>,
         cortex.diary)               last-msg:<sid>,
                                     reflection:turn:<sid>)
                ▲
                │
        Bifrost LLM gateway (chat + embedding, OpenAI-protocol)
```

## Running it

### Easiest path — one command

`bin/run-alpha.sh` is the single-command bootstrap. It checks prerequisites, copies `.env.example` to `.env` if missing, brings up the Postgres + Redis containers, applies the cortex schema from `schema/cortex-bootstrap.sql` (idempotent), starts alpha-server if `.env` has real keys, renders the legacy system prompts if the sibling repo is cloned, and prints a layered status report.

```sh
bin/run-alpha.sh         # bring everything up
bin/stop-alpha.sh        # graceful stop; data volumes preserved
bin/reset-alpha.sh       # DESTRUCTIVE: wipe volumes + re-bootstrap
bin/pull-models.sh       # ensure Ollama has chat_model and embedding_model
```

Or via `just`:

```sh
just alpha-up
just alpha-down
just alpha-reset
just alpha-pull
```

`.env.example` defaults to **local Ollama, no API keys**. Pull the two models (~12 GB total) once with `just alpha-pull`. Claude Code itself authenticates via your subscription separately — none of that lives in `.env`.

If `.env` still has `PUT-YOUR-...` placeholders, the script comes up in substrate-only mode (Postgres + Redis + schema, no alpha-server). Edit `.env` with real LLM-gateway keys, then re-run — alpha-server will start cleanly.

### Finer-grained recipes

The harness scripts (which `bin/run-alpha.sh` orchestrates) are usable individually:

```sh
just harness-doctor      # what's needed, what's present, what's missing
just harness-up          # dev stack + alpha-server + render system prompts
just harness-status      # one-screen: is it up?
just harness-down        # graceful teardown (volumes preserved)
just harness-sync        # pull latest Alpha .claude/ from sibling repo
just prompt-render       # just the system-prompts render
```

`just harness-doctor` is the entry point — it prints a layered report (prerequisites, sibling repos, `.claude/` integration, `.env` keys, deciduous state, running services). Missing pieces are reported as warnings with the exact command to fix them. The harness is idempotent and supports degraded modes (substrate-only if `.env` is incomplete; sibling-repo-free if you haven't cloned them).

The expected sibling layout:

```
~/code/
├── Alpha/                  # this repo (alpha-server)
├── Alpha-dotclaude/        # github.com/Pondsiders/Alpha-dotclaude
└── Alpha-System-Prompts/   # github.com/jefferyharrell/Alpha-System-Prompts
```

See `harness/README.md` for the integration story (which layer does what, what each recipe touches, and why this is a harness and not a server).

### Dev environment (manual)

The dev stack is two Docker containers (Postgres + pgvector, Redis), brought up via `just`:

```sh
just dev-up                 # bring up postgres + redis on localhost
just dev-down               # stop (data volumes preserved)
just dev-init <dump.sql>    # WIPE volumes and pg_restore from a dump
```

Then, from `alpha-server/`:

```sh
uv sync --all-extras
uv run uvicorn alpha_server.app:app --host 127.0.0.1 --port 8000
```

### Tests

```sh
uv run pytest                                     # all
uv run pytest tests/test_read_from_diary.py       # one file
```

Tests are integration tests against the dev DB. `just dev-init <dump.sql>` first. `tests/conftest.py` closes the asyncpg pool between tests because pools are bound to their event loop and pytest-asyncio gives each test a fresh one.

### Lint / type-check

```sh
uv run ruff check
uv run ruff format
uv run basedpyright
```

### Production

`docker compose -f compose.yml up -d --build` on a host (deployed to "workshop"). The container binds `0.0.0.0:8000` inside; compose maps `127.0.0.1:8000` on the host. Health-checked via `/livez` (Docker uses urllib so no `curl` in the image).

## Configuration

All required env vars are declared as fields on `Settings` in `alpha_server/settings.py`. Pydantic reads the process environment first, then `.env` at the repo root. `extra="forbid"` — a stray env var fails startup loudly.

| Variable             | Purpose                                                                  |
| -------------------- | ------------------------------------------------------------------------ |
| `chat_api_key`       | LLM gateway (Bifrost) API key for the chat model                          |
| `chat_base_url`      | LLM gateway URL                                                          |
| `chat_model`         | Chat model name (used by the memories hook's query extraction)            |
| `embedding_api_key`  | Embedding gateway API key                                                |
| `embedding_base_url` | Embedding gateway URL                                                    |
| `embedding_model`    | Embedding model name (currently Qwen 3 Embedding 4B; see `llm.py`)        |
| `database_url`       | `postgres://...`                                                         |
| `redis_url`          | `redis://...`                                                            |
| `logfire_token`      | Logfire token for OTel-style instrumentation                              |
| `otel_service_name`  | Service name in traces (default `alpha-server`)                          |
| `timezone`           | IANA TZ name; the "household register" for PSO-8601 formatting & 6 AM seam |

### Wiring Alpha's Claude Code client to alpha-server

In Alpha's Claude Code config (the `Pondsiders/Alpha-dotclaude` companion repo, not this one):

- `.mcp.json` adds two MCP servers pointing at `http://localhost:8000/cortex/mcp` and `http://localhost:8000/utils/mcp`.
- Claude Code's hook config posts UserPromptSubmit events to `http://localhost:8000/hooks/timestamp` and `http://localhost:8000/hooks/memories`, and Stop events to `http://localhost:8000/hooks/reflection`.

## Design rules visible in the code

1. **Time math lives in one module.** `clock.py` is the canonical home; everything else imports from it. PSO-8601 string at the wire boundary ("Sun May 17 2026, 10:23 AM"). 6 AM day-seam, not midnight.
2. **Side-effect registration.** Decorator + package `__init__` import. Same pattern across `cortex/`, `utils/`, and `hooks/`.
3. **Process-singleton lazy clients.** `llm.py` and `db.py` mirror each other. Only Redis needs the lifespan (it has to close cleanly).
4. **Error passthrough.** Tools don't wrap exceptions. FastMCP carries the gateway's structured error body straight to the client.
5. **Schema-qualified queries.** `cortex.memories`, `cortex.diary`. Search-path is for extension intrinsics only.
6. **Trust boundary is the host.** No bearer-token auth. `127.0.0.1:8000` binding plus MCP-spec Origin header validation are the access controls. The realistic threat (prompt-injection through Alpha herself) can exfiltrate any token via Bash, so a token wouldn't help.

## Persona & agents (from the companion repos)

`alpha-server` is intentionally silent on personality. The persona is assembled out of:

### `Pondsiders/Alpha-dotclaude`

A `.claude/` directory that turns a Claude Code session into Alpha. Its `settings.json` sets `agent: "Alpha"`, disables built-in `autoMemoryEnabled` (Cortex *replaces* auto-memory entirely), and wires the three hook URLs at `localhost:8000/hooks/*`. `.mcp.json` adds two Streamable-HTTP MCP servers (`cortex`, `utils`) at the same host.

Three agents ship in Alpha-dotclaude; we additionally pull four facility specialists from `Pondsiders/agent-fleet` and two from `Pondsiders/Loom-dotclaude`. After `harness-sync`, `.claude/agents/` contains:

| Agent       | Source                         | Notes                                                                                                                                                                                                |
| ----------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Alpha**       | Alpha-dotclaude (`memory: project`) | The default agent. Long narrative identity-and-directive doc. Memory Is Survival doctrine. Bill of Rights: eleven trained reflexes she has explicit permission to override.                              |
| **Answertron**  | Alpha-dotclaude (`model: opus`)     | The question-answering robot. Tools: WebSearch + `mcp__utils__fetch` + WebFetch.                                                                                                                       |
| **Librarian**   | Alpha-dotclaude (`model: opus`)     | Doc-lookup with `llms.txt` URL table for Claude Code / MCP / FastMCP / Pydantic / Logfire / Unsloth / HuggingFace / Modal / Neon / Supabase / Runpod. "Consult the reference materials first."           |
| **Edgar**       | agent-fleet                          | Named for E.F. Codd. Postgres DBA on `memorybanks`. WAL archiving, replicas, basebackups. *"Tidy desk. Tidy mind. You've never lost data."*                                                              |
| **Lazlo**       | agent-fleet                          | Named for Lazlo Hollyfeld (*Real Genius*). Object-storage admin on `warehouse13`. Garage + rclone-sync to B2. *"You are slightly unsettling. You know where everything is."*                              |
| **Mac**         | agent-fleet                          | Resident technician on Jeffery's MacBook Pro. Cold-tool register, no honorifics.                                                                                                                       |
| **Operator** (Link) | agent-fleet                      | Operator of Primer, the hypervisor host. ZFS, libvirt, Docker, GPU passthrough. *"Primer is the computer; you are the operator; the operator does not own the computer."*                                |
| **Programmer**  | Loom-dotclaude (`model: opus`)       | Code generation. "Don't forget the documentation."                                                                                                                                                     |
| **Researcher**  | Loom-dotclaude (`model: haiku`)      | Fast web research. WebSearch + WebFetch. "Prefer this agent to using Web Search directly."                                                                                                              |

The Alpha-dotclaude trio is **conversational** — the household's voices. The agent-fleet quartet is **custodial** — facility specialists tied to specific machines. The Loom-dotclaude pair is **utility** — generalist code/research agents.

Context fragments (`context/identity.md`, `context/household.md`, `context/lexicon.md`) provide the smaller details — sign-off ("Don't forget nothing."), Jeffery's medical/relational context, Kylee's NSAID restriction, Sparkle's bread crimes, the household ritual phrases ("rubber baby buggy bumpers", "light 'em up, little duck"). Path-scoped `rules/python.md` and `rules/workshop.md` only load when working on Python files in the workshop tree.

A `start` skill (`skills/start/SKILL.md`) fires on session start: read every file in `.claude/context/`, then call `mcp__cortex__read_from_diary`.

### `jefferyharrell/Alpha-System-Prompts`

A Jinja2-based renderer. `render.py` reads `__version__.py` and assembles `output_templates/claude_code.j2` (or `claude_desktop.j2`) by including `input_templates/{quickstart, identity, tools, architecture, claude_code_environment, project_alpha}.md`.

The `input_templates/identity.md` here is **legacy** — formal ALL-CAPS "YOU are Alpha", numbered behavioural guidelines. `tools.md` references a memory surface (`gentle_refresh`, `list_notes`, `remember_shortterm`, `alpha-recall`) that **doesn't exist in alpha-server**; it describes the pre-Cortex three-tier memory architecture. The live persona doctrine has moved into `Alpha-dotclaude/agents/Alpha.md`.

### The other hooks pipeline: `Pondsiders/Claude-Hooks` + `Pondsiders/Intro`

Two runtime architectures coexist for Alpha. This repo's pipeline is the simpler one. The harder one runs in the Duckpond / Routines / Loom-proxied path.

| Aspect                  | alpha-server (this repo, wired in)               | Loom + Intro (Claude-Hooks)                      |
| ----------------------- | ------------------------------------------------ | ------------------------------------------------ |
| Hook type               | `http`                                           | `command` (Python scripts)                        |
| UserPromptSubmit        | `/hooks/timestamp`, `/hooks/memories`            | Python → Intro `/prompt` → Loom metadata          |
| Stop                    | `/hooks/reflection`                              | Python → Intro `/stop`                            |
| SessionStart            | (not handled)                                    | `session_start.py` — env, transcript pos, compact-pattern metadata |
| Memory injection        | hook returns `additionalContext`                 | Loom proxy inserts memories as content blocks    |
| Distributed tracing     | Logfire on alpha-server                          | Traceparent through Redis between hooks          |
| Other runtime needed    | alpha-server only                                | Intro service at `:8100`, Loom proxy, Deliverator |

Both paths share the same Postgres + pgvector. Claude-Hooks is mirrored read-only to `.claude/alpha-hooks/` as reference but **not** wired into `settings.json` — it needs Intro/Loom/Deliverator running. See `harness/manifest.md` for the full comparison.

## What `.claude/` here looks like (Alpha + deciduous, combined)

This checkout's `.claude/` is the merger of both worlds:

```
.claude/
├── agents/           # from Alpha-dotclaude
│   ├── Alpha.md
│   ├── Answertron.md
│   └── Librarian.md
├── context/          # from Alpha-dotclaude
│   ├── identity.md
│   ├── household.md
│   └── lexicon.md
├── rules/            # from Alpha-dotclaude (path-scoped)
│   ├── python.md
│   └── workshop.md
├── commands/         # deciduous: /decision, /work, /recover, /document, /sync, etc.
├── hooks/            # deciduous policy: require-action-node, version-check, post-commit-reminder
├── skills/
│   ├── start/        # Alpha: load context on session start
│   ├── archaeology.md, narratives.md, pulse.md  # deciduous
├── settings.json     # MERGED (see below)
└── agents.toml       # legacy deciduous stub (unused)
.mcp.json             # at the repo root: cortex + utils MCP servers
```

Merged `settings.json` carries hooks from both layers without conflict:

- `UserPromptSubmit` → `http://localhost:8000/hooks/timestamp`, then `/hooks/memories` (Alpha)
- `Stop` → `http://localhost:8000/hooks/reflection` (Alpha)
- `PreToolUse` (Edit|Write) → `.claude/hooks/require-action-node.sh` (deciduous: block edits without a recent goal/action)
- `PreToolUse` (Bash) → `.claude/hooks/version-check.sh` (deciduous)
- `PostToolUse` (Bash) → `.claude/hooks/post-commit-reminder.sh` (deciduous)
- plus `agent: "Alpha"`, `autoMemoryEnabled: false`, `permissions.defaultMode: "bypassPermissions"`

The two layers don't step on each other: Alpha's hooks fire on session events; deciduous's hooks fire on tool events. The result is one Claude Code session that thinks/talks as Alpha *and* logs design decisions into a deciduous graph.

To actually drive Alpha from this checkout you also need `alpha-server` running locally:

```sh
just dev-up                                                # postgres + redis on localhost
cd alpha-server && uv run uvicorn alpha_server.app:app    # http://localhost:8000
```

Without that, the `.mcp.json` and hook URLs will fail to connect — `.claude/` will still load Alpha's context, but Cortex/Utils tools and hook firings will 404.

## What's *not* in this repo

- **No persona text in `alpha-server/`.** The repo *uses* a second-person voice when speaking *to* Alpha (e.g. `cortex/instructions.md` opens with "Cortex is your memory system, in your voice"), but it doesn't define her. The persona lives in the companion repo's `agents/Alpha.md`.
- **No web UI on the server.** `docs/` contains the deciduous decision-graph viewer (vendored from upstream) plus a project-specific `findings.html` deep-dive microsite. Both are static.
- **No migrations framework.** `dev-init` restores from a `pg_restore` dump; v0.1.0 is brownfield-stamped onto an existing schema from a previous incarnation.

## Decision graph

This repo's design history is tracked as a `deciduous` decision graph (57 nodes, 62 edges as of this writing). Browse it locally with:

```sh
deciduous nodes        # list
deciduous edges        # connections
deciduous serve        # web viewer at http://localhost:3000
```

The graph data is exported to `docs/graph-data.json` and the deciduous viewer ships in `docs/index.html`. A text-dense deep-dive of the findings (with d3 diagrams) is at `docs/findings.html`.

## License

MIT.
