# Flaky and fast — determinism, speed, parallelism

## The flaky test taxonomy

| Source | Symptom | Fix |
|---|---|---|
| **Time** | Passes 3PM, fails 11:59PM | Inject clock; avoid `now()` in asserts |
| **Randomness** | Fails ~5% of runs | Seed RNG; inject id generators |
| **Order** | Passes solo, fails in suite | Isolate state; scoped fixtures |
| **Concurrency** | Fails under `-n auto`, passes solo | Fix the real concurrency bug; don't disable |
| **Shared resource** | Port clashes, DB deadlocks | Ephemeral ports; isolated DBs |
| **Network** | Fails when external API slow | Mock or record (VCR); don't call real APIs |
| **Filesystem** | Leaks between tests | `tmp_path` fixtures; no hard-coded `/tmp/x` |
| **Timing / sleep** | `sleep(0.1)` "works on my machine" | Wait for condition, not for time |
| **Async** | Intermittent, different stack trace each time | Await everything; no fire-and-forget |

## The deterministic-clock pattern

**Anywhere production code touches time, accept a `Clock` dependency:**

```python
from datetime import datetime
from typing import Protocol

class Clock(Protocol):
    def now(self) -> datetime: ...

class SystemClock:
    def now(self) -> datetime:
        return datetime.utcnow()

class FixedClock:
    def __init__(self, t: datetime) -> None:
        self._t = t
    def now(self) -> datetime:
        return self._t
    def advance(self, delta: timedelta) -> None:
        self._t += delta
```

Production wires `SystemClock`. Tests wire `FixedClock` and advance
manually.

Libraries that help: `freezegun` (Python), `jest.useFakeTimers()`,
`@sinonjs/fake-timers`. But injectable is always preferred.

## Deterministic IDs

```python
class IdGenerator(Protocol):
    def new(self) -> UUID: ...

class SystemIdGenerator:
    def new(self) -> UUID: return uuid4()

class SequentialIdGenerator:
    def __init__(self) -> None: self._n = 0
    def new(self) -> UUID:
        self._n += 1
        return UUID(int=self._n)
```

In tests, sequential IDs are readable in assertions (`UUID(int=1)`
vs. `af93-...`).

## Waiting for conditions, not for time

### Bad

```python
submit_job()
time.sleep(1)
assert job_done()
```

Flaky: 1s might be too short; wastes time if job finishes in 50ms.

### Good

```python
def poll(condition: Callable[[], bool], timeout: float = 5.0) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if condition():
            return
        time.sleep(0.05)
    raise AssertionError(f"Condition not met within {timeout}s")

submit_job()
poll(lambda: job_done())
```

Libraries: `waiting` (Python), `wait-for-expect` (JS), Kotlin's
`awaitility`.

## Parallelizing the suite

Benefits: huge speedup (4–8× common). Forces better test hygiene
(state leaks become visible).

### Python pytest

```bash
pytest -n auto              # use all CPUs
pytest -n 4 --dist=loadfile # split by file for DB-heavy tests
```

Plus `pytest-xdist`.

### JS Jest

```json
{ "jest": { "maxWorkers": "50%" } }
```

### Setup

- Each worker must have its own DB schema (or a scoped unique prefix
  per worker).
- Environment variables that change per-worker (ports, paths) use
  `PYTEST_XDIST_WORKER` or equivalent.
- Avoid session-scoped mutable fixtures.

## Isolating the database

### Transaction rollback pattern

Open a transaction at test start, roll back at end. Fastest. Works
when the code under test doesn't open its own top-level transaction
(or you use savepoints).

```python
@pytest.fixture
def db_session() -> Generator[Session, None, None]:
    connection = engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection)
    try:
        yield session
    finally:
        session.close()
        transaction.rollback()
        connection.close()
```

### Truncate-and-seed pattern

Truncate all tables, re-seed fixtures, per test. Works always.
Slower. Parallelizes by having one DB per worker.

### Per-test ephemeral DB

TestContainers gives you one Postgres per test session, per worker.
Combine with transaction rollback per test.

## Test order independence

Any test must pass when run:

1. In isolation (`pytest path/to/test_x.py::test_y`).
2. Twice (`pytest path/to/test_x.py::test_y path/to/test_x.py::test_y`).
3. In a random order (`pytest --randomly-seed=123`).

If any of these fails → shared-state bug. Fix it (don't sort the
suite to "work around").

Useful tools: `pytest-randomly`, `jest --randomize`.

## The "slow suite" playbook

Symptoms: CI takes 15+ minutes, devs skip local runs.

Diagnose:

1. **Profile.** Every test runner supports per-test timing (`pytest --durations=20`).
2. **Identify the top 10 slowest.** Usually 80% of the time.
3. **Classify.** Fixture setup? DB migrations? External calls? Real sleeps?

Common wins:

- **Parallelize.** Flat 4× speedup.
- **Make DB migrations once per session**, reset state via truncate/
  transaction.
- **Replace `sleep(5)` with polling.** Slashes e2e time.
- **Cache expensive fixture data** (session scope, not function
  scope).
- **Mock/record external APIs** (VCR, WireMock).
- **Parallel test containers** — one per worker, reused.
- **Delete tests that duplicate coverage** (not everything has to
  be tested at every level).

## Flake rate tracking

- CI captures pass/fail per test per run.
- Report `flakes_per_1000_runs` per test, sorted.
- Quarantine rule: > 1% flake rate over N runs → auto-skip + open
  ticket. Unreliable tests that stay green by chance erode trust.
- Deflake or delete. Don't "retry until passes" for business logic
  tests.

## Test impact analysis (TIA)

For large repos, only run tests affected by a given change.

- **File-based** — simple graph of "test file X depends on src Y".
  Fast approximation. Tools: `nx affected`, `bazel`, `pytest-testmon`.
- **Coverage-based** — record which tests hit which lines; map diff
  lines to tests. More accurate, more infra.

TIA cuts PR CI time 5–10×. Not worth the infra under 2000 tests; at
20000+ tests, indispensable.

## Debugging a specific flake

1. **Reproduce in isolation**: run the test 1000× — does it fail?
2. **Reproduce in the suite**: if only fails in suite, bisect test
   order to find the poisoning neighbor.
3. **Isolate environmental**: does it fail when the DB is empty /
   full / slow? Under load?
4. **Log the random state** (seed, IDs, times) at test start.
5. **Print-debug the test infrastructure** — your assertion is fine;
   the fixture is lying.

## Determinism of async code

Pitfalls:

- **Unawaited tasks** — `asyncio.create_task(f())` with no `await`.
  Test finishes before the task does.
- **`asyncio.sleep` in tests** — bad unless paired with `FakeClock`.
- **Concurrent access to shared state in tests** — use a `Lock` or
  serialize.

Use `pytest-asyncio` for Python; ensure each test has its own event
loop (function scope).

## CI-specific flakes

- **OS differences** (Linux vs macOS paths, line endings).
- **Timezone** — pin to UTC in CI; set `TZ=UTC` or inject clock with
  an explicit timezone.
- **Locale** — `LANG=C.UTF-8`.
- **Disk space** — full disk = flaky fixture failures.

## The "fix it now" rule

When a test becomes flaky:

- **Today** — do not merge over a flake. Revert or fix.
- **This week** — diagnose and deflake properly.
- **Never** — mark it xfail and forget.

Letting flakes stay sets the norm that CI can be ignored. The suite
becomes decorative.
