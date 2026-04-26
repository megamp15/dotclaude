---
name: python-async-patterns
description: asyncio correctness for service code — loops, cancellation, blocking I/O, MagicStack ecosystem (uvloop, asyncpg, httptools)
source: stacks/python
alwaysApply: false
triggers: asyncio, async def, await, uvloop, asyncpg, httptools, aiohttp, httpx, starlette, fastapi, anyio, trio
---

# Python async patterns

Applies to services that run on asyncio — FastAPI, Starlette, aiohttp,
bare asyncio workers. The MagicStack flavor of this (`uvloop` +
`asyncpg` + `httptools`) is a 2–4× throughput lift for I/O-bound
workloads; the rules below assume that or the stdlib loop.

## The cardinal rule

**Never block the event loop.** A single synchronous call — `requests.get`,
`time.sleep`, a CPU-heavy regex, `psycopg2` in sync mode, reading a large
file without `aiofiles`, bcrypt on the main loop — stalls every other
in-flight request. This is the #1 cause of "async Python is slow"
complaints.

If a function is `async def`, every I/O call inside it must be async, or
delegated to a thread/process via `asyncio.to_thread` / `run_in_executor`.

## Use `asyncio.run` only at the top

- `asyncio.run(main())` exactly once, in the entry point.
- Never inside a function called from async code. Nested `asyncio.run` creates a new loop and corrupts library state.
- In tests, use the test framework's async support (`pytest-asyncio`, `anyio`), not hand-rolled `asyncio.run`.

## Event loop: prefer uvloop where available

```python
# service bootstrap
try:
    import uvloop
    uvloop.install()  # or asyncio.set_event_loop_policy(uvloop.EventLoopPolicy())
except ImportError:
    pass
```

Notes:

- uvloop is Linux/macOS. On Windows, skip silently.
- uvicorn auto-detects uvloop if installed; you don't need to call `install()` yourself when running under uvicorn with `--loop uvloop` (or default auto).
- uvloop changes timing behavior subtly. Keep the fallback path so tests and dev on Windows still work.

## Concurrency primitives — pick the right one

- **`asyncio.gather(...)`** — fan out N independent awaitables, collect N results. Fails fast on first exception (use `return_exceptions=True` if you want to inspect all outcomes).
- **`asyncio.TaskGroup`** (3.11+) — structured concurrency. Prefer over `gather` in new code: cleaner cancellation, all child tasks cancelled if any raises.
- **`asyncio.as_completed`** — same fan-out, process results as they land.
- **`asyncio.Queue`** — producer/consumer with backpressure.
- **`asyncio.Semaphore`** — cap concurrency against an upstream (e.g. "at most 10 concurrent DB queries", "at most 5 concurrent outbound HTTP per caller").

```python
# cap outbound fan-out to avoid DoSing the dependency
sem = asyncio.Semaphore(10)

async def fetch_one(url):
    async with sem:
        return await client.get(url)

results = await asyncio.gather(*(fetch_one(u) for u in urls))
```

## Cancellation

Cancellation is a feature, not an error. Handle it correctly:

- **`asyncio.CancelledError` should propagate.** Don't swallow it in a bare `except Exception`. If you need cleanup on cancel, catch it, run cleanup, **re-raise**.
- **Shield critical sections** with `asyncio.shield(...)` when a cancellation shouldn't abort mid-operation (e.g. mid-write to a ledger).
- Long-running loops should check for cancellation naturally — every `await` is a checkpoint. Pure-CPU loops inside `async def` block cancellation.

```python
try:
    await long_operation()
except asyncio.CancelledError:
    await cleanup()
    raise  # re-raise, don't swallow
```

## Timeouts

**Every external call has a timeout.** The default in most clients is
"forever."

```python
# 3.11+
async with asyncio.timeout(5.0):
    result = await external_call()

# older
result = await asyncio.wait_for(external_call(), timeout=5.0)
```

Prefer `asyncio.timeout` (context manager) over `wait_for` when available — it composes better with nested timeouts.

## HTTP clients

- **`httpx`** — ergonomic; works both sync and async. Use `AsyncClient` with a **module-level singleton** or FastAPI/Starlette lifespan-bound instance. Not per-request — each creates a new connection pool.
- **`aiohttp`** — thinner, faster for raw throughput. `ClientSession` is the pool; share it.
- Never `await httpx.AsyncClient().get(...)` inline — the client is constructed and dropped, re-pooling every call.

```python
# app startup
app.state.http = httpx.AsyncClient(
    timeout=httpx.Timeout(5.0, connect=2.0),
    limits=httpx.Limits(max_connections=100, max_keepalive_connections=20),
)
# app shutdown: await app.state.http.aclose()
```

## Databases

- **`asyncpg`** — Postgres. Significantly faster than psycopg's async mode. Use a **pool**, not a single connection.
- **`aiosqlite`** — SQLite async wrapper; SQLite itself is serialized, so concurrency ≤ 1 writer.
- **`sqlalchemy[asyncio]`** — async ORM over asyncpg/aiomysql/aiosqlite. Works, but knows less than raw asyncpg about prepared-statement lifetimes; watch for pgbouncer incompatibility.

Pool rules:

- Size the pool to match peak concurrent workers, not request count. "Pool of 100" on a service that runs 4 uvicorn workers = 400 connections to the DB.
- Always release connections — use `async with pool.acquire() as conn:` or equivalent context manager. Leaked connections kill throughput.
- **Never hold a DB connection across `await` on an external HTTP call.** The connection is locked while you wait on something else.

## Thread / process offloading

- CPU-bound work → `await asyncio.to_thread(fn, *args)` for quick wins; `run_in_executor(ProcessPoolExecutor(), fn, ...)` for actual parallelism past the GIL.
- Sync libraries with no async equivalent (e.g. `boto3` — though `aioboto3` exists) → `to_thread`. Measure; sometimes sync-in-thread is faster than a second-rate async library.
- **bcrypt / argon2 → always `to_thread`.** They're CPU-heavy and block the loop for tens of ms per call.
- File I/O → `aiofiles` for actual async, or `to_thread` for one-off.

## Testing

- `pytest-asyncio` or `anyio` plugin.
- One fixture per connection/client, scoped to `session` or `module` — creating a pool per test is absurdly slow.
- Use `anyio` for tests that should work under both asyncio and trio if your library supports both.

## Common mistakes (look for these in review)

| Symptom | Likely cause |
|---|---|
| "Async code is slower than sync" | Blocking call inside `async def` stalling the loop |
| Connection pool exhaustion | Not releasing on error path, or holding across external await |
| Intermittent timeouts | No per-request timeout; slow upstream chews the caller's budget |
| Hangs on shutdown | Pending tasks not cancelled; lifespan not awaiting `aclose()` |
| Test deadlocks | Mixed sync + async DB drivers; or a sync fixture blocking the loop |
| `Task was destroyed but it is pending` warning | Background task not awaited or cancelled on shutdown |

## MagicStack recipe (opt-in)

For max throughput on Linux:

```
uvloop        # event loop
httptools     # HTTP parser (uvicorn picks up automatically)
asyncpg       # Postgres driver
httpx         # outbound HTTP (or aiohttp)
```

With `uvicorn --loop uvloop --http httptools`, throughput is typically
2–4× the stdlib defaults for I/O-bound services. Keep the fallback path
so dev on Windows still boots.
