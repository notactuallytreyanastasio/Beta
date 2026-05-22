# Narratives — Alpha repository deep dive

The Alpha repo is `alpha-server`: a Python FastAPI app that wires a stateful AI persona ("Alpha", whom Jeffery Harrell speaks to) into Claude Code via two surfaces — an MCP tool server ("Cortex") and a hook router.

## Cast of characters (from the repo, not outside knowledge)

- **Jeffery** — the user. "He is a human, a tinkerer and a dilettante." (`hooks/memories_extract_queries.md`)
- **Alpha** — "the AI to whom he is speaking; she is more than one year old, stateful and unique." (same file)
- **Alpha-OLD / Alpha-App** — predecessor repos. Reflection-reminder text was "lifted verbatim from Alpha-App's suggest.py with two edits" (commit `ce66e50`). Memories hook is "ported from Alpha-OLD's user_prompt_submit hook" (commit `4cd4a9b`).
- **protoalpha** — the dev/testbed Claude Code project. End-to-end verifications happen "through Claude Code on protoalpha". (`13fcb2c`, `ca6cf59`, `eb98278`)
- **workshop** — Jeffery's machine; the container host. "Trust boundary is the host (workshop VM)." (`e9e606c`)
- **alpha-DB** — separate DB host reachable on the tailnet. (`c221875`)
- **Bifrost** — the LLM gateway. "preserves Bifrost's structured JSON error body verbatim" (`8b72a88`); chat + embedding calls routed through it (`d66e85e`).
- **Pondside / Pondsiders** — the umbrella ecosystem of related repos: `Pondsiders/Alpha-dotclaude` (Claude Code settings), `/Pondside/.claude/rules/python.md` (shared rules). (`f7085d1`, `4cd4a9b`, `ca6cf59`)

## Narrative 1 — Bootstrapping the substrate

Concepts: FastAPI factory, FastMCP, pgvector, schema discipline.

- `3a880f0` initial commit — empty
- `ba3881c` project stub
- `13fcb2c` First end-to-end working alpha-server: FastAPI app, Cortex MCP at `/cortex/mcp`, bearer-token auth, `/livez`, lifespan hand-off composing FastMCP's session manager with FastAPI's. Five fields in Settings: `database_url`, `timezone`, `auth_token`. asyncpg pool, pgvector registered against `extensions` schema, `search_path=public, extensions` as a startup parameter (not SET, because SET gets wiped on connection reset).
- `acc6222` Tiny fix: MCP `serverInfo` was leaking FastMCP's own version. `importlib.metadata.version("alpha-server")` makes `pyproject.toml` the single source of truth.

## Narrative 2 — Cortex tool surface (diary + memories)

Concepts: the diary (continuity letter), memories (semantic), tool surface mechanics, model registration via decorators.

The tool surface evolved opinionated decisions across seven commits:

- `eb98278` `add_to_diary` lands. "Brittle-as-fuck doctrine — caller bugs should surface, not hide behind polite validation."
- `cf703d6` `get_schema` — derive cortex schema DDL dynamically from `information_schema.columns` at call time. "The dynamic-from-Postgres approach means the description never goes stale."
- `ba76c4f` `execute_query` — read-only SQL escape hatch, 5s statement_timeout. "Recall is fuzzy and probabilistic; SQL is precise and grammatical." pgvector embeddings rendered as `<vector len=N>`; datetimes coerced to PSO-8601.
- `7fffea7` **REVISIT**: `execute_query` and `get_schema` retired in favor of `search_memories` (two modes: semantic cosine, FTS via `ts_rank_cd`). Same commit refactors LLM clients into a new `llm.py` module mirroring `db.py` — lazy module-level singletons, no lifespan handoff. `format_query_for_embedding` is centralized; "explicitly coupled to Qwen 3 Embedding 4B and called out as the seam to revisit on any model swap."
- `8b72a88` `store_memory` + the **error-passthrough pattern**: do NOT catch embedding or DB exceptions; FastMCP turns them into `CallToolResult(isError=True)` preserving Bifrost's structured JSON error body verbatim. autouse pytest fixture resets `db._pool` between tests (asyncpg pools are bound to their event loop).
- `75893a8` `recent_memories` (limit 1..100, oldest-first within batch).
- `5cfaa2f` `get_memory` — fetch by id. "Earns its keep" because ids appear in recall output, diary entries, conversation references.

Tool surface is registered via side-effect imports: `cortex/__init__.py` imports each tool module, each module decorates a function with `@mcp.tool`. The decorator is the registration.

## Narrative 3 — Recall pipeline (memories hook)

Concepts: UserPromptSubmit hook, query extraction, embedding fan-out, Redis seen-cache.

- `4cd4a9b` `/hooks/memories` — the seven-step recall pipeline:
  1. Chat model extracts JSON-array of semantic queries from prompt
  2. Embed each query (originally one HTTP request per query)
  3. Pull `seen:<session_id>` from Redis
  4. Fan out cosine searches over pool (top-1 per query)
  5. Merge/dedupe by id, filter `score < 0.1`
  6. SADD new ids to seen-set with 7-day TTL
  7. Format as `## Memory #...` blocks, return as `additionalContext`

Substrate landed alongside: Redis 8 service in `compose-dev.yml`, six new Settings fields for chat/embedding clients.

- `3afd399` Batched query embeddings into one request. "The embedding endpoint processes inputs serially under the hood either way... one batched request... costs a single roundtrip. The tensor cores get to do their job in one forward pass instead of N."

## Narrative 4 — Hooks router refactor + timestamp + reflection

Concepts: shared `APIRouter`, side-effect registration mirroring the MCP tool pattern, Stop-hook decision:block envelope.

- `ca6cf59` `/hooks/timestamp` lands. Same commit refactors: the per-file `APIRouter` pattern from `memories.py` was "the right shape for one hook and the wrong shape for the four-plus we now know we're going to have." Single shared `APIRouter` in `hooks/__init__.py`; side-effect imports in `app.py` trigger registration. **Mechanism-side consistency with `cortex/__init__.py`.** Same commit adds `clock.elapsed(earlier, later)` as a sibling to `clock.age(dt)`.

- `ce66e50` `/hooks/reflection` — the **novel piece**. Stop hooks don't use `additionalContext`; they return `{"decision": "block", "reason": <text>}` which keeps the turn from ending AND feeds `reason` to the model as the instruction to continue. Fires on turns 1, 4, 7, 10, ... via atomic Redis `INCR`. Short-circuits on `stop_hook_active=true` to avoid the 8-block runaway-override path. **Reminder text framed as "between turns": the model is told this reminder is from alpha-server, not from Jeffery, and not to reference it in the eventual reply.**

## Narrative 5 — Auth & trust boundary

Concepts: bearer-token, prompt-injection threat model, MCP-spec Origin validation, port binding.

- `13fcb2c` First version: `BearerTokenMiddleware` with `hmac.compare_digest`, bypass for `/livez`.
- `c221875` Auth commented out as a Desktop-over-SSH compatibility workaround; tailnet treated as bounded blast radius.
- `e9e606c` **Drop bearer-token auth entirely.** "Bearer tokens stored in env vars and .mcp.json files don't move the security needle against the realistic threat in our deployment. Prompt-injection through me can read both via Bash. The token is exfiltrable by the same path that gives the attacker a request channel." The trust boundary becomes the host.
- `67bce90` Bind production port to `127.0.0.1:8000` explicitly (the `8000:8000` shorthand had bound `0.0.0.0`; the previous claim was "aspirational, not real").
- `40328ba` `OriginValidationMiddleware` — the MCP-spec MUST. Allow-list is `{None, ""}` (non-browser clients in this deployment don't send Origin). Empirically verified via FastMCP probe.

## Narrative 6 — Containerization

Concepts: Dockerfile two-stage uv sync, `.dockerignore`, compose overrides.

- `c221875` Big architectural pivot ("from this morning's Mr-Bones chalkboard, memory #17598"): host-process-behind-Tailscale-sidecar → containerized on Workshop with `127.0.0.1:8000` port mapping. Container reaches Postgres+Redis on alpha-DB over tailnet from inside Workshop.
- `df39a4b` `.dockerignore` + uv cache mount. The `COPY of alpha-server/` was clobbering the container's built venv with the host's 299MB `.venv` (timed: 9.3s → 1.0s → 3.4s after fix).
- `79a56c1` Per-checkout compose overrides (`compose.override.yml.example` tracked; the real `compose.override.yml` gitignored). One workshop checkout can run dev mode on port 8001 with project name `alpha-dev`; production stays on `:8000`.

## Narrative 7 — Utils MCP server

Concepts: second MCP server mounted alongside, three-tier markdown fetch, SSRF defense.

- `49af2ca` `/utils/mcp` lands as a sibling to `/cortex/mcp`. First (and only) tool: `fetch` — URL → Markdown in three tiers:
  1. `Accept: text/markdown` header (Cloudflare-rendered sites, doc generators)
  2. URL variants — `/foo` → `/foo.md`/`/foo.mdx` (Mintlify-style)
  3. trafilatura HTML extraction

  `_ssrf.py` resolves the URL host and rejects any non-global address (private, loopback, link-local, reserved, multicast, plus Tailscale CGNAT). Tool instructions explicitly tell the LLM to **prefer `fetch` over `WebFetch`** because WebFetch's "extra LLM step is lossy for content that's already well-structured."

  Same commit composes the second MCP lifespan via `AsyncExitStack` so adding another mounted MCP server is "a single `enter_async_context` line."

## Narrative 8 — Observability (TTFT)

Concepts: Logfire instrumentation, scrubbing whitelist for `session_id`.

- `d66e85e` Logfire added to investigate sustained 1m+ TTFT tail latency. `instrument_fastapi`, `instrument_httpx`, `instrument_asyncpg`, `instrument_openai`. Each hook handler wrapped in `logfire.span("hooks.<name> {session_id}", session_id=...)`. Inner phase spans inside `memories._run`: `extract_queries`, `embed_queries`, `search_db`. Custom scrubbing callback whitelists `session_id` only (Logfire's default scrub-pattern includes `session`); other matches stay scrubbed.

> "Empirically confirmed via tcpdump that Claude Code does not propagate a traceparent header to hook URLs (plain axios/1.13.6 without OTel HTTP instrumentation), so we can't unify into a single trace with Claude Code's separate OTel stream. session_id (present in every hook JSON envelope) plus wall-clock is the cross-stream join key."

## Cross-cutting design rules (visible in the code)

1. **Time lives in one module.** `clock.py` is the canonical home; other modules don't import `datetime`/`time`/`pendulum`. PSO-8601 string at the wire boundary, datetime in code, ISO-8601 in Postgres. 6 AM day-seam.
2. **Side-effect registration.** Tool/hook modules decorate against a shared registry; the package `__init__` (or `app.py`) imports them. Adding a tool/hook means write the module + add to the side-effect import.
3. **Process-singleton lazy clients.** `llm.py` (chat, embedding) and `db.py` (asyncpg pool) follow identical shapes. Redis is the only client that needs the lifespan (lives on `app.state.redis`).
4. **Error passthrough.** Don't wrap; FastMCP surfaces uncaught exceptions cleanly. "Brittle-as-fuck doctrine."
5. **Schema-qualified queries.** Application tables always written `cortex.memories`, `cortex.diary`. Search-path is for extension intrinsics only.
6. **`extra="forbid"` on Settings.** A stray env var fails startup loudly.
7. **Cortex vs auto-memory.** "Auto-memory is for facts. Cortex is for moments." Facts are third-person, evergreen, edited (e.g. preferences). Moments are first-person, time-stamped, textured.
