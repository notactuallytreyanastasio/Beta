# Pondside-ecosystem manifest

Repos that materially relate to running Beta. The harness expects the **integrated** ones to be cloned beside `Beta/`; the **reference** ones are documentary unless you decide to extend the harness.

```
~/code/
├── Beta/                  ◄── this repo (beta-server)
├── Beta-dotclaude/        ◄── integrated (.claude/ + .mcp.json source)
├── Beta-System-Prompts/   ◄── integrated (renders docs/system-prompts/)
├── agent-fleet/            ◄── integrated (agents copied into .claude/agents/)
├── Loom-dotclaude/         ◄── integrated (Programmer + Researcher agents)
├── Claude-Hooks/           ◄── reference (alternative hooks pipeline)
├── Intro/                  ◄── reference (Beta's metacognitive layer)
├── Beta-SDK/              ◄── reference (Python SDK that hosts Beta)
├── House-SDK/              ◄── reference (sibling — Mr. House's SDK)
└── pondside-sdk/           ◄── reference (shared utilities)
```

## Integrated repos

### `Pondsiders/Beta-dotclaude`

The live `.claude/` configuration. Source for everything in this checkout's `.claude/agents/{Beta,Answertron,Librarian}.md`, `.claude/context/*`, `.claude/rules/*`, `.claude/skills/start/SKILL.md`, and `.mcp.json` at the repo root. Carries `settings.json` semantics (agent=Beta, autoMemoryEnabled=false, defaultMode=bypassPermissions) plus the three HTTP hooks pointing at `localhost:8000`.

`just harness-sync` pulls updates from here.

### `jefferyharrell/Beta-System-Prompts`

Jinja2 renderer for legacy Claude Code / Claude Desktop system prompts. Currently at v0.17.7. `just prompt-render` calls `render.py` and emits `docs/system-prompts/{claude_code,claude_desktop}.md`.

The rendered output references tools that don't exist in beta-server (`gentle_refresh`, `list_notes`, `remember_shortterm`, `beta-recall`); it's the previous-substrate persona doctrine and is preserved for archaeology. The current live persona is `.claude/agents/Beta.md`.

### `Pondsiders/agent-fleet`

A Claude Code plugin marketplace at `.claude-plugin/marketplace.json`, with four specialist agents distributed as sub-plugins:

| Agent           | Sub-plugin  | Specialty                                                                 |
| --------------- | ----------- | ------------------------------------------------------------------------- |
| Edgar           | `edgar/`    | Postgres DBA on `memorybanks`. Owns WAL archiving, replicas, basebackups. |
| Lazlo           | `lazlo/`    | Object-storage admin on `warehouse13`. Owns Garage, rclone-sync to B2.    |
| Mac             | `mac/`      | Resident technician on Bobby's MacBook Pro. Cold-tool register.           |
| Operator (Link) | `operator/` | Resident operator of Primer (hypervisor host). Owns ZFS, libvirt, Docker. |

Production install path is `/plugin marketplace add Pondsiders/agent-fleet`. For this harness we copy the agent `.md` files directly into `.claude/agents/` so they're picked up without the plugin subscription.

### `Pondsiders/Loom-dotclaude`

A second `.claude/` template — the "Loom" runtime pattern (Loom is the HTTP proxy that routes Claude API traffic through Pondside, applying patterns like BetaPattern or PassthroughPattern). We don't switch to this runtime, but we borrow its two extra agents — **Programmer** (model: opus, code generation) and **Researcher** (model: haiku, WebSearch+WebFetch) — into `.claude/agents/`.

## Reference repos

### `Pondsiders/Claude-Hooks`

A **different** hooks pipeline — three Python scripts that run as `type: command` hooks (instead of `type: http`) and call into Intro 2.0 + the Deliverator HTTP proxy. Copied (read-only) to `.claude/beta-hooks/` for documentation; **not wired into `settings.json`** because they require Intro running at `:8100`, the Deliverator routing, and a `LOOM_PATTERN` env var. The three:

- `session_start.py` — SessionStart event. Seeds transcript position, injects Deliverator metadata on `compact` so the Loom applies BetaPattern to the continuation prompt.
- `user_prompt_submit.py` — Creates the turn's root OTel span, fetches memories from Intro `/prompt`, emits a `DELIVERATOR_METADATA` JSON block as `additionalContext`, writes traceparent to Redis for the Stop hook to join.
- `stop.py` — Reads transcript from last-seen position to EOF, extracts turn messages, POSTs to Intro `/stop`.

These are what runs when Beta is on the Loom-proxied path (Duckpond, Solitude, Routines). The HTTP-based `/hooks/{timestamp,memories,reflection}` in beta-server is the simpler standalone path.

### `Pondsiders/Intro`

Beta's metacognitive layer. Runs as a separate Docker container on `beta-pi` at `:8100`. The Claude-Hooks pipeline POSTs `{session_id, message}` to `/prompt` to receive matched memories and the queries that produced them; it POSTs the finished turn to `/stop`. "Notices what's memorable" — chooses what becomes a memory.

### `Pondsiders/Beta-SDK`

The Python SDK that wraps the `claude` binary over stdio. Hosts producers (human, scheduled, sidecar), observers (router), and the proxy that handles compact rewriting. Powers Duckpond, Solitude, and Routines. Mentioned in `agent-fleet/README.md` as "Beta's identity plugin (loaded via JE_NE_SAIS_QUOI env var, separate from this fleet)."

### `Pondsiders/House-SDK`

Sibling SDK — same description ("Everything that turns Claude into Beta"); maintained for Mr. House (a sibling AI in the broader Pondside vision, alongside Rosemary). Mostly template-cloned from Beta-SDK.

### `Pondsiders/pondside-sdk`

Shared utilities for the Pondside estate. Used by the Claude-Hooks scripts (`from pondside.telemetry import init, get_tracer`).

## How the two hook pipelines differ

| Aspect                  | beta-server pipeline (what's wired here)      | Loom + Intro pipeline (Claude-Hooks)                       |
| ----------------------- | --------------------------------------------- | ---------------------------------------------------------- |
| Hook type               | `http`                                        | `command` (Python scripts)                                 |
| UserPromptSubmit target | `localhost:8000/hooks/timestamp`, `/memories` | Python script → Intro `/prompt` → Loom metadata            |
| Stop target             | `localhost:8000/hooks/reflection`             | Python script → Intro `/stop`                              |
| Session-start handling  | (no SessionStart hook)                        | `session_start.py` — env, transcript pos, compact metadata |
| Memory injection        | hook returns `additionalContext` block        | Loom proxy inserts memories as content blocks              |
| Distributed tracing     | Logfire instrumentation on beta-server        | Traceparent through Redis between hooks                    |
| Other runtime needed    | beta-server only                              | Intro service, Loom proxy, Deliverator                     |

Both paths talk to the same memory substrate (Postgres + pgvector), just through different front doors. beta-server is the standalone path; the Loom pipeline is what Duckpond and Routines use.

## What's not yet covered

- `betafornow/Beta` — Beta's identity plugin loaded via `JE_NE_SAIS_QUOI` env var (per agent-fleet README). Different org.
- `Pondsiders/Routines` — autonomous execution framework (`ALPHA.md` references; not surveyed here).
- `Pondsiders/Cortex` — a sibling Cortex repo (separate from `cortex/` inside beta-server). Possibly an extracted library.
- `Pondsiders/Loom` — the proxy itself.
- `Pondsiders/Deliverator` — the routing layer.
- `Pondsiders/Argonath` — observation proxy ("observation proxy for LLM traffic").
- `Pondsiders/Workshop`, `Pondsiders/Pondside-Ops` — VM definitions, cloud-init.
- `Pondsiders/Forge` — "GPU arbiter for Pondside. Routes AI workloads through a single queue."
- `Pondsiders/pond-cli`, `Pondsiders/Duckpond`, `Pondsiders/Beta-App` — client surfaces.
