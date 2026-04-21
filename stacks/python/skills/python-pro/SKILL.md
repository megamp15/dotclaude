---
name: python-pro
description: Deep Python 3.11+ expertise beyond style — typing (generics, Protocols, overload, TypedDict, ParamSpec), async (asyncio + trio/anyio), performance (profiling, C extensions, asyncio pitfalls), packaging with `uv`, and testing patterns (fixtures, factories, property-based, freezegun). Extends the rules in `stacks/python/CLAUDE.stack.md` and `stacks/python/rules/python-style.md`.
source: stacks/python
triggers: /python-pro, advanced python, python typing, protocols, TypedDict, ParamSpec, overload, asyncio patterns, trio, anyio, python performance, cProfile, py-spy, asyncio pitfalls, uv lock, pytest fixtures, hypothesis, property-based testing, package layout
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/python-pro
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# python-pro

Production-grade Python 3.11+ expertise for people who already know the language.
Activates when someone asks "how should I type this", "why is this async slow",
"is this the right packaging layout", or any question that goes past style.

> **See also:**
>
> - `stacks/python/CLAUDE.stack.md` — baseline conventions (uv, ruff, mypy --strict)
> - `stacks/python/rules/python-style.md` — enforceable rules
> - `stacks/python/rules/async-patterns.md` — the async rules (this skill adds
>   design guidance and failure modes)
> - `stacks/fastapi/skills/fastapi-expert/` — if the question is framework-shaped

## When to use this skill

- Designing a public API surface with generics, Protocols, or overloads.
- Diagnosing asyncio slowness, cancellation issues, or "why does `asyncio.gather`
  hang".
- Turning a `src/`-layout package into something you can publish or install
  from a private index with `uv`.
- Picking between `dataclass`, `attrs`, `pydantic`, and `TypedDict` for a given
  role.
- Writing pytest that is fast, parametrized, and free of fixture spaghetti.

## References (load on demand)

- [`references/typing.md`](references/typing.md) — `Protocol`, `TypedDict`,
  `NotRequired`, `Literal`, `ParamSpec`, `TypeVarTuple`, `@overload`, `Self`,
  `Unpack`, variance. Plus mypy-strict survival tips.
- [`references/async.md`](references/async.md) — asyncio vs. trio/anyio,
  structured concurrency, cancellation, `TaskGroup`, pitfalls around
  `gather(return_exceptions=True)`, the "sync-in-async" trap, and how to profile.
- [`references/performance.md`](references/performance.md) — profiling
  (`cProfile`, `py-spy`, `scalene`), common wins (dict over list for lookups,
  `__slots__`, LRU cache, vectorizing), and when to reach for Cython / Rust.
- [`references/packaging.md`](references/packaging.md) — `pyproject.toml` shape,
  `uv` workflows, src-layout, entry points, private indices, editable installs.
- [`references/testing.md`](references/testing.md) — fixture design, factories,
  property-based testing with `hypothesis`, time control with `freezegun`, and
  async testing with `pytest-asyncio`.

## Core workflow

1. **Classify the question** — typing / async / perf / packaging / testing.
   Load the relevant reference instead of dumping all five.
2. **Check the baseline** — if the user's code violates `python-style.md` the
   fix is almost always "follow the rule first, then optimize".
3. **Write it small** — a minimum reproducer, a minimum type signature, a
   minimum benchmark. Don't speculate about perf.
4. **Measure before optimizing** — every perf answer starts with a profile.
   No micro-optimization without evidence.
5. **Prefer stdlib** — `dataclasses`, `functools`, `itertools`, `contextlib`,
   `asyncio`, `pathlib` cover most needs before reaching for a library.

## Defaults (fast decisions)

| Question | Default |
|---|---|
| Simple immutable record | `@dataclass(frozen=True, slots=True)` |
| Structured I/O boundary | `pydantic.BaseModel` (V2) |
| Dict-shaped API response / config | `TypedDict` with `NotRequired` |
| Duck-typed interface | `Protocol` (runtime-checkable only if needed) |
| Generic container | `Generic[T]` + bounded `TypeVar` |
| Sync function that might block | run in `asyncio.to_thread()` from async code |
| Multiple awaitables | `asyncio.TaskGroup` — not bare `gather()` |
| Retry / timeout | `async with asyncio.timeout(...):` + `tenacity` |
| CLI | `typer` (or `argparse` if you don't want a dep) |
| Data pipeline | generators + `itertools`, not pandas, unless tabular |

## Anti-patterns

- `from typing import List, Dict, Tuple` in 3.11+ code — use built-ins.
- `Optional[X]` where you mean "nullable" — use `X | None`.
- Catching `Exception` at a boundary without re-raising or structured logging.
- `async def` functions that call blocking I/O without `to_thread`.
- `asyncio.gather(*tasks)` with no error handling — one exception cancels the
  rest silently if you use `return_exceptions=True`, or surfaces only the first
  if not. Use `TaskGroup`.
- `pip install` in README when the stack is `uv` — copy-paste rot.
- Module-level side effects (DB connections at import time) — breaks testing,
  breaks forking, breaks everything.
- Sprawling `conftest.py` chains. A fixture used in 2 test files lives in the
  nearest common conftest, not the root one.

## Output format

For typing / API questions:

```
Signature:
    <the type>

Why this shape:
    <1–2 sentences>

If the caller passes <X>:
    <mypy behavior>

Alternative if <constraint>:
    <the alternative>
```

For perf / async debugging:

```
Hypothesis:
    <what you think is slow>

Evidence needed:
    <which profile / log>

Likely fix:
    <the fix>

Escape hatch:
    <C extension / process pool / rewrite>
```
