# Async Python — asyncio, structured concurrency, pitfalls

## Which library?

| Need | Use |
|---|---|
| FastAPI / anything Starlette-based | `asyncio` (the event loop is already running) |
| Library that should work on asyncio *and* trio | `anyio` |
| You control the whole stack and want best-in-class cancellation | `trio` |

Default: `asyncio`. Reach for `anyio` only when writing a cross-runtime library.

## Structured concurrency with `TaskGroup` (3.11+)

Prefer `TaskGroup` over `gather`. It cancels siblings on failure and
aggregates exceptions into `ExceptionGroup`.

```python
import asyncio

async def fetch_all(urls: list[str]) -> list[bytes]:
    results: list[bytes] = [b""] * len(urls)
    async with asyncio.TaskGroup() as tg:
        for i, url in enumerate(urls):
            tg.create_task(_fetch_into(i, url, results))
    return results

async def _fetch_into(i: int, url: str, sink: list[bytes]) -> None:
    sink[i] = await _http_get(url)
```

If any `_fetch_into` raises, `TaskGroup` cancels the others and re-raises as
`ExceptionGroup`. Use `except*` to handle specific types:

```python
try:
    await fetch_all(urls)
except* asyncio.TimeoutError as eg:
    logger.warning("some requests timed out: %d", len(eg.exceptions))
except* Exception as eg:
    logger.exception("unexpected: %s", eg.exceptions)
```

## `asyncio.gather` — when it's OK

Only when *all* coroutines are independent and you genuinely want partial
success semantics:

```python
results = await asyncio.gather(*tasks, return_exceptions=True)
for item in results:
    if isinstance(item, Exception):
        # handle per-item failure
```

Without `return_exceptions=True`, the first failure cancels the rest but you
only see that first exception — the others are swallowed.

## Timeouts

Modern form:

```python
async with asyncio.timeout(30):
    data = await fetch_slow_thing()
```

Per-try timeouts inside a retry loop:

```python
async with asyncio.timeout_at(deadline):
    ...
```

Avoid `asyncio.wait_for(..., timeout=...)` for new code — it has edge cases
around cancel propagation that `timeout()` fixes.

## Cancellation

Cancellation is an exception (`asyncio.CancelledError`). It propagates like any
other exception, but you should not catch and suppress it:

```python
try:
    await long_running()
except asyncio.CancelledError:
    await cleanup()                # do your cleanup
    raise                          # MUST re-raise
```

Shielding a critical section:

```python
await asyncio.shield(flush_to_disk())
```

`shield` protects the *shielded* coroutine; the outer scope can still be
cancelled, so you typically want `shield` + `try/finally`.

## The "sync-in-async" trap

Calling a blocking function (`requests.get`, `open(...).read()`, `psycopg2`,
`time.sleep`) from an async function **blocks the entire event loop**. Symptoms:
tail latency spikes, health checks time out, concurrency collapses to ~1.

Fixes, in order:

1. **Use an async-native library** (`httpx`, `asyncpg`, `aiofiles`).
2. **Offload to a worker thread**:
   ```python
   data = await asyncio.to_thread(blocking_fn, arg)
   ```
3. **For CPU-bound** work (JSON parse of 50MB, image resize), offload to a
   process pool:
   ```python
   loop = asyncio.get_running_loop()
   with ProcessPoolExecutor() as pool:
       result = await loop.run_in_executor(pool, cpu_work, arg)
   ```

Detecting it in production: enable `loop.set_debug(True)` in dev or run with
`PYTHONASYNCIODEBUG=1` — it logs any task that blocks the loop > 100ms.

## Backpressure with `Semaphore` / `Queue`

```python
async def fetch_with_limit(urls: list[str], max_concurrent: int = 10) -> list[bytes]:
    sem = asyncio.Semaphore(max_concurrent)

    async def bounded(url: str) -> bytes:
        async with sem:
            return await _http_get(url)

    async with asyncio.TaskGroup() as tg:
        tasks = [tg.create_task(bounded(u)) for u in urls]
    return [t.result() for t in tasks]
```

For producer/consumer patterns use `asyncio.Queue` with `maxsize` — an
unbounded queue hides memory leaks.

## Locks, Events, Conditions

Use only when needed. Most async code is stateless per-task. When you do need
them:

- `asyncio.Lock` for one-at-a-time regions (not for perf — async already
  serializes at the loop).
- `asyncio.Event` for one-shot notifications.
- `asyncio.Condition` for multi-waiter coordination.
- Never hold a lock across `await` unless that's the *point* of the lock.

## Testing async code

```python
import pytest

@pytest.mark.asyncio
async def test_fetch_all() -> None:
    results = await fetch_all(["http://a", "http://b"])
    assert len(results) == 2
```

Configure in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

For time-sensitive tests, monkeypatch `asyncio.sleep` or use `freezegun`.

## Common pitfalls

| Symptom | Cause | Fix |
|---|---|---|
| "Task was destroyed but it is pending" | You never `await`ed a task | Keep a reference *and* await it |
| Task silently swallowed an error | `fire-and-forget` with `create_task` and no completion handler | `task.add_done_callback(log_errors)` or use `TaskGroup` |
| Process hangs on shutdown | Open connections / tasks not cancelled | Use `async with` for resources; run loop with `asyncio.run()` which cancels pending tasks |
| `RuntimeError: Event loop is closed` in pytest | Leaking tasks across tests | Use `pytest-asyncio`'s `event_loop` fixture; don't call `asyncio.run` inside tests |
| Sub-second latency spikes | Blocking call in async path | `PYTHONASYNCIODEBUG=1` to find it; `to_thread` or async library |

## Profiling async

- `py-spy dump --pid <pid>` — stack of every task, live.
- `py-spy record -o out.svg -- python app.py` — flamegraph, includes async
  frames.
- Built-in: `asyncio.all_tasks()` + `task.get_stack()` for ad hoc dumps.
