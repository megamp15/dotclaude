# Pytest patterns

## Fixture design

Fixtures scope-up the thing being shared:

```python
import pytest

@pytest.fixture(scope="session")
def db_url() -> str:
    return "postgresql://test@localhost/test"

@pytest.fixture
def client(db_url: str) -> Iterator[TestClient]:
    app = make_app(db_url)
    with TestClient(app) as c:
        yield c
```

Scopes, in order of speed: `session` > `module` > `class` > `function`
(default). Use the broadest scope that still gives test isolation.

A fixture used in one test file lives at the top of that file. A fixture
used in two or more files lives in the *nearest common* `conftest.py`.
Don't put everything in the root `conftest.py` — it becomes a god-module.

## Parametrize instead of loops

```python
@pytest.mark.parametrize(
    "input_, expected",
    [
        ("1", 1),
        ("-2", -2),
        ("0", 0),
    ],
    ids=["positive", "negative", "zero"],
)
def test_parse_int(input_: str, expected: int) -> None:
    assert parse_int(input_) == expected
```

`ids` gives readable test names in reports (`test_parse_int[zero]`).

## Factories over fixture chains

If you need "a user, but with X overridden" in many tests, use
`pytest-factoryboy` or write small builder functions:

```python
def make_user(**overrides) -> User:
    return User(**{"id": 1, "email": "a@b.com", "role": "member", **overrides})
```

Cleaner than a fixture tree where `admin_user` depends on `user` depends on
`db_session`.

## Property-based testing with Hypothesis

Use for invariants — "for any input of shape X, Y must hold":

```python
from hypothesis import given, strategies as st

@given(st.integers(), st.integers(min_value=1))
def test_divmod_roundtrip(a: int, b: int) -> None:
    q, r = divmod(a, b)
    assert q * b + r == a
    assert 0 <= r < b
```

Good targets: parsers, serializers, encoders/decoders, business rules with
"no matter what" clauses. Bad targets: anything where you have to enumerate
the valid space yourself.

## Time control

```python
from freezegun import freeze_time

@freeze_time("2026-04-17 12:00:00")
def test_token_expiry() -> None:
    token = issue_token(ttl_seconds=3600)
    assert not token.is_expired()
```

For tests that advance time, use `pytest-freezer` or monkeypatch
`time.monotonic`. Don't sleep in tests.

## Async tests

`pytest-asyncio` with `asyncio_mode = "auto"` (in `pyproject.toml`) means
you don't need `@pytest.mark.asyncio` on every test.

```python
async def test_fetch(client: httpx.AsyncClient) -> None:
    r = await client.get("/health")
    assert r.status_code == 200
```

Shared async fixtures:

```python
import pytest_asyncio

@pytest_asyncio.fixture
async def client() -> AsyncIterator[httpx.AsyncClient]:
    async with httpx.AsyncClient(base_url="http://test") as c:
        yield c
```

## Mocking

Preference order:

1. **Dependency injection** — pass a fake object.
2. **`monkeypatch`** — patch a specific attribute for the test's duration.
3. **`unittest.mock.patch`** — last resort, and only when you can't
   restructure the call site.

```python
def test_sends_email(monkeypatch: pytest.MonkeyPatch) -> None:
    calls: list[str] = []
    monkeypatch.setattr("myapp.mail.send", lambda addr, body: calls.append(addr))
    register_user("a@b.com")
    assert calls == ["a@b.com"]
```

Patch where the name is *used*, not where it's defined:

```python
# myapp/user.py
from myapp.mail import send
def register(email): send(email, "Welcome")

# In tests
monkeypatch.setattr("myapp.user.send", fake_send)   # NOT myapp.mail.send
```

## Snapshot / approval testing

Good for: complex output (OpenAPI specs, rendered templates, JSON payloads).
Use `pytest-snapshot` or `syrupy`.

Bad for: things with timestamps, ordering differences, or secrets. Normalize
first.

## Coverage

```toml
[tool.coverage.run]
source = ["src"]
branch = true

[tool.coverage.report]
exclude_also = [
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
    "@overload",
    "pragma: no cover",
]
skip_covered = false
show_missing = true
```

Target: 85%+ for library code, less is fine for apps as long as public
behavior is covered. 100% coverage is a trap — you end up testing
implementation.

## Fast test suites

- Run in parallel: `pytest -n auto` (`pytest-xdist`).
- `--lf` (last failed) and `--ff` (failed first) during dev.
- Mark slow tests: `@pytest.mark.slow` and `pytest -m "not slow"` for the
  default path.
- Keep DB fixtures at `session` scope with per-test transactions (rollback
  in teardown).
- Avoid real network. Use `httpx.MockTransport` or `respx`.

## When tests become a liability

Signals:

- "Fix the test" is normal during refactors (meaning tests pin
  implementation).
- A change in one file breaks 20 unrelated tests.
- Mocks mock mocks.

Fix: write more tests at the *public API* level and fewer at the unit level.
Classical / Chicago-school > mockist / London-school for most codebases.

## Debugging a failing test

Tight loop, in this order:

1. Run just the failing test with full traceback:
   `uv run pytest path/to/test.py::test_name -xvs --tb=long`
2. If it passes in isolation but fails in the suite, suspect shared state
   (fixtures with `session`/`module` scope, env vars, tmpdir reuse). Isolate
   by progressively narrowing the run set.
3. Drop `breakpoint()` into the failing line and re-run with `-s` to land in
   pdb. From there: `where`, `args`, `pp <expr>`.
4. For flaky tests, run with `--count=20` (`pytest-repeat`) to reproduce
   reliably before attempting a fix. A flake you can't reproduce is a flake
   you can't fix.
5. Before declaring it fixed, run the full suite once: `uv run pytest`.
   Don't trust an isolated pass — fixes often break neighbors.
