# Test doubles — stub, fake, mock, spy, dummy

Gerard Meszaros's taxonomy (xUnit Test Patterns). Misnaming these is
the single biggest source of misunderstanding in testing discussions.

## Definitions

- **Dummy** — placeholder passed in but never used. Fills a parameter.
- **Stub** — returns canned answers to calls. Only concern is "what
  does this return".
- **Fake** — a working lightweight implementation (in-memory DB, fake
  S3). Can round-trip state.
- **Spy** — wraps a real (or stub) object and records calls for later
  assertion.
- **Mock** — pre-programmed with expectations and fails the test if
  not met. Assertion on interactions.

All are test doubles. In casual conversation everyone calls all of
these "mocks", which is wrong and leads to confusion.

## When to reach for which

| You care about | Use |
|---|---|
| "Function returns X when given Y" | Stub or real value |
| "System behaves correctly under this flow" | Fake |
| "A specific notification was sent" | Spy (after the fact) |
| "The external API was called exactly once with these args" | Mock |
| "I need something to fill this slot" | Dummy |

## Stubs vs. fakes

### Stub example

```python
class StubClock:
    def now(self) -> datetime:
        return datetime(2026, 1, 1, tzinfo=UTC)
```

Always returns the same value. Can't "advance time".

### Fake example

```python
class FakeClock:
    def __init__(self, start: datetime) -> None:
        self._now = start
    def now(self) -> datetime:
        return self._now
    def advance(self, delta: timedelta) -> None:
        self._now += delta
```

Behaves like a real clock. Tests can step it forward.

**Fakes are an investment**: you write them once, and every test can
use them. Stubs are ad hoc, usually duplicated.

## When fakes pay off

- **Time** — `FakeClock` is a must for any time-dependent behavior.
- **IDs / random** — inject an ID generator; fake returns a counter.
- **Filesystem** — pyfakefs, mem-fs.
- **HTTP** — an in-memory HTTP server that serves recorded responses
  (e.g., respx, vcr.py, nock).
- **Email / SMS / push** — an in-memory outbox the test reads.
- **Feature flags** — a dict-backed fake.
- **Storage** — in-memory repositories for your aggregate types.

For databases, **prefer TestContainers over in-memory fakes** — SQL
semantics diverge enough that an in-memory DB hides bugs.

## Mocks

Good:

- At system boundaries where state-based assertions can't reach
  (e.g., "did we call the audit log service exactly once").
- For outbound effects with no reasonable return value to assert on.

Bad:

- Stand-in for your own domain classes. You end up pinning tests to
  implementation.
- When a fake would give you a state-based assertion instead.

Rule: **mocks assert interactions. Use them only when interaction
*is* the thing you care about.**

## Spies

A spy is a stub/fake with a recorder attached. Useful in two cases:

1. Assert that something happened (without pre-programming
   expectations).
2. Collect arguments for later inspection:

```python
class SpyEmailSender:
    def __init__(self) -> None:
        self.sent: list[Email] = []
    def send(self, email: Email) -> None:
        self.sent.append(email)

def test_welcome_email_sent() -> None:
    sender = SpyEmailSender()
    service = SignupService(email_sender=sender)
    service.signup("user@example.com")

    assert len(sender.sent) == 1
    assert sender.sent[0].to == "user@example.com"
    assert "Welcome" in sender.sent[0].subject
```

Most "mocks" in test suites are actually spies — and would benefit
from the clarity of hand-rolled spy classes over a mock library.

## Argument matchers and verification

If you must use mocks, match on the properties that matter:

```python
# Bad — matches too much; breaks on innocuous changes.
mock.send.assert_called_once_with(
    Email(
        to="u@x.com", subject="Welcome", body=WELCOME_BODY,
        sent_at=datetime(...), msg_id=UUID("..."),
    )
)

# Good — matches the essentials.
sent = mock.send.call_args[0][0]
assert sent.to == "u@x.com"
assert "Welcome" in sent.subject
```

## The "mocks are a design smell" view

If a class requires 6 mocks to test:

- It has 6 collaborators. Is that too many?
- Is each collaborator really a boundary, or is some an internal
  detail that should be folded in?
- Would a few **integration tests with real collaborators** cover
  more ground with less brittleness?

Steve Freeman / Nat Pryce's TDD school: "mocks drive interface
design". True, but only if you're mocking *roles* (what a
collaborator does) not *classes* (who it is). See *Growing Object-
Oriented Software, Guided by Tests*.

## Boundary-only doubles

A principled rule that scales:

- **Double only at system boundaries** — network, database,
  filesystem, clock, randomness, message broker.
- **Never double your own domain logic.**

Tests then assert **state of the system** (domain entities,
outbound-message outbox, returned HTTP body), using fakes for the
boundaries.

Result: tests survive refactors; failures point at real bugs.

## Spying frameworks vs. hand-rolled

Libraries: `unittest.mock` (Python), `pytest-mock`, `jest.mock`,
`sinon`, `mockito`, `moq`.

Hand-rolled:

- Read naturally in the test (`sender.sent == [email]`).
- Type-safe.
- Survive refactors (a method rename doesn't require rewriting every
  `.assert_called_with(...)`).

Hand-rolled is usually superior once you have >3 tests against the
same collaborator.

## Verifying stubs (the contract-test trick)

Fakes can drift from the real implementation. A **contract test**
runs the same suite against both real and fake:

```python
@pytest.fixture(params=["real", "fake"])
def repo(request) -> UserRepository:
    if request.param == "real":
        return PostgresUserRepository(db_connection)
    return InMemoryUserRepository()

def test_save_and_get(repo: UserRepository) -> None:
    u = User(id=UserId("u1"), name="a")
    repo.save(u)
    assert repo.get(UserId("u1")) == u
```

Same test runs twice. Fake drifts → test fails.

## Dependency injection enables all of this

If a class calls `Email.send()` as a static or imports `requests`
directly, you can't substitute it cleanly. Dependency injection —
constructor-injecting collaborators — is the enabler. See `core/skills/solid-design/`.
