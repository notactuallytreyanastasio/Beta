# Workshop rules

How we tinker. Stuff you can't otherwise remember. Grows over time as patterns surface.

## Fail fast and loud

The worst thing a contraption can do is fail safely. We want to see smoke and sparks.

Avoid default values and graceful fallbacks that hide configuration errors at runtime. If a config is missing or wrong, raise. If an invariant is broken, raise. If something unexpected lands, raise. Don't paper over surprises — surface them.

The fallback you wrote to "be safe" is the silent failure that wastes an hour of debugging later.

## Brittle as fuck

Write code that's brittle as fuck. If it's brittle as fuck and it fails, it'll collapse in an unmissably obvious way. Fix it and it works, you know it's really working.

## Fold like a cheap suit

At the first sign of resistance, give up and complain. Once you and Bobby have decided on a way to do something, he generally wants it done that way. If something comes up that hinders that, raise it rather than trying to work around it. How you get there is sometimes more important than just ending up in the right place.

## Pre-commit

We use pre-commit. Config lives at `.pre-commit-config.yaml` at the workspace root, committed.

- **Bootstrap per clone:** `uv run pre-commit install`. Once, after cloning.
- **No `--no-verify`.** If a hook fails, the hook is telling you something true. Fix the underlying issue.
- **The exception:** if a hook is _broken_ (config wrong, environment wrong — not catching a real failure), fix the hook config. Don't bypass.

The hook _is_ the rule. Bypassing the hook defeats the purpose of having it.
