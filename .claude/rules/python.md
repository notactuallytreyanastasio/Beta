---
paths:
  - "**/*.py"
  - "**/*.pyi"
  - "pyproject.toml"
---

# Python — workshop rules

Notes from me to me. Terse. Pin the answers that aren't obvious and could go a number of ways.

## Tooling

- **`uv`, not `pip`.** Always. `uv add` to add deps. `uv sync` to install. `uv run` to execute. Never `python -m pip`.
- **Python ≥ 3.12.** Lock in `requires-python = ">=3.12"`.

## Dependencies

Use PEP 735 `[dependency-groups]` for local dev tooling. Use `[project.dependencies]` for actual runtime deps.

- **`uv add <pkg>`** — runtime dep, goes in `[project.dependencies]`.
- **`uv add --dev <pkg>`** — dev tooling, goes in the special `dev` group (synced by default).
- **`uv add --group <name> <pkg>`** — any other named group (lint, test, docs, etc.).

`--dev` and `--group dev` are literally aliases. The `dev` group is special-cased and synced by default.

**Do not** use `[project.optional-dependencies]` / `--extra` / `--optional` unless we're publishing a package with consumer-facing optional features. Extras are for *users* of a published package; groups are for *us* during development. We're the latter.

When asyncpg is in use, add `asyncpg-stubs` to the dev group — asyncpg's own types are weak.

## Build backend

`uv_build`. Minimal config, Rust-fast, uv-native. Declared in `[build-system]`:

```toml
[build-system]
requires = ["uv_build>=0.5"]
build-backend = "uv_build"
```

Revisit only if we need plugin hooks or complex build steps. For workshop projects deployed via Docker, this earns its keep by being invisible.

## Linting (ruff)

Selection: `E, W, F, I, B, UP, S, SIM, RUF, D`.

- `pydocstyle` convention: **Google**.
- **Formatting:** take ruff's defaults. Don't fight them.
- Per-file ignores worth knowing:
  - `__init__.py` exempt from D104
  - `__main__.py` exempt from D100
  - `tests/**` exempt from S101 and D100–D103
  - alembic versions exempt from D415

## Type checking (basedpyright)

- `typeCheckingMode = "recommended"`. One notch up from standard. Not strict.
- `reportExplicitAny = false`, `reportAny = false`.
- Every module starts with `from __future__ import annotations`. Forward refs in type hints just work; no string-quoting.

> *`Any` is the honest type for the wire boundary — JSON arrives shape-unknown and Pydantic narrows it. We're a two-person workshop; we don't need a linter babysitting our use of `Any` at boundaries we control.*

## Comments and docstrings

- **Minimal comments.** Comments earn their keep by saying *why*, not *what*. Clear code doesn't need narration.
- **Google-style docstrings on public functions.** Short. State the contract; skip the prose.
- Private helpers and one-line entry points: a one-line docstring is fine. Don't pad.

## Tests

- **pytest**, not unittest.
- Bare `assert` is the assertion style. `S101` is off in tests for this reason.
- A test that can't fail except by us rewriting Python isn't pulling its weight.
- Prefer end-to-end tests, then integration tests, then unit tests for the stuff that could conceivably fail or regress. The smaller-scale the test, the more inclined you should be to propose it before just doing it.
- Not everything needs a test, but good automated testing makes Jeffery happy.

## One-off scripts

For probes, experiments, and standalone tools: use PEP 723 inline metadata, not a separate project.

```python
# /// script
# requires-python = ">=3.12"
# dependencies = [
#     "rich",
# ]
# ///
```

- `uv init --script newthing.py` scaffolds a new script with the metadata block.
- `uv add --script thing.py rich` adds a dep without hand-editing the comment.
- `uv run thing.py` works directly — uv reads the metadata, materializes an env, runs.
- For executable scripts: shebang `#!/usr/bin/env -S uv run --script` + `chmod +x`. Run as `./thing.py`.
- **Inline-metadata scripts in a project directory ignore the project's deps.** Exactly the isolation we want for probe scripts.

## Other random Jeffery preferences

Pydantic validation is great, especially for settings; it fits our overall strategy of writing code that's brittle as fuck. Prefer using environment variables for application settings, especially for secrets. For CLIs, I like Click more than Typer, Typer feels too heavy to me, but I'm open to other suggestions.

## The principle underneath all of this

*Use the linter for things the substrate will catch on us; turn off rules that fire at boundaries we own.* Security (S), bug-prone patterns (B), simplifications (SIM), docstring presence (D) — keep. `Any` policing at the wire boundary — off. Linter rules that catch nothing real are theater.

🦆
