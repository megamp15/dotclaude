# The pyramid, honeycomb, diamond — and when each fits

## The classic pyramid

```
        /\
       /E2E\       few, slow, brittle
      /------\
     /  Int   \    moderate, realistic
    /----------\
   /    Unit    \  many, fast, focused
   --------------
```

Works when:

- The service has rich domain logic that can be unit-tested in
  isolation.
- Integration points are mostly well-covered libraries (Postgres,
  Redis) rather than bespoke orchestration.

## The honeycomb (Spotify-style)

```
  /  e2e  \
  ---------
  | integ |
  | integ |       dominant middle layer
  | integ |
  ---------
  \  unit /
```

Works when:

- The service is mostly glue — HTTP routing, service-to-service,
  queue consumers. Unit tests of "call A then B" don't add value.
- A TestContainers-backed integration test is almost as fast as a
  unit test.

## The trophy (Kent C. Dodds for frontends)

```
      E2E      (few)
   --------
   Integration (many)
   --------
     Unit
   --------
    Static
```

Works when:

- You have a frontend with components that should be tested the way
  users use them (React Testing Library), with fewer unit tests on
  render logic.

## Picking yours

Questions:

1. **What changes most often?** Test there.
2. **Where is a bug most expensive?** Bias tests there.
3. **What's a realistic "wrong"?** Tests should be able to catch it.
4. **What's cheap?** TestContainers vs. real cloud — real cloud is
   slow + flaky + expensive.

## Classical vs. mockist

- **Classical (Detroit / Chicago)** — test behavior via state
  assertions on real collaborators, using real or fake dependencies.
  Tests survive refactors.
- **Mockist (London)** — each class tested in isolation with mocked
  collaborators, asserting interactions.

Mockist trade-offs:

- Pros: strictly pinpoint failure location; drives interface design.
- Cons: tests pinned to implementation; refactors break many tests;
  verifies "did we call X" not "did the system behave correctly".

Modern consensus: **classical by default**, mockist only for
boundaries (network, filesystem, clock, randomness). Especially in
statically typed codebases, mockist is usually overkill.

## What belongs at each level

### Unit

- Pure functions: parsers, validators, formatters.
- Domain logic: business rules, calculations.
- Isolated classes with simple dependencies (or fakes).

### Integration

- DB queries against a real DB (TestContainers Postgres, etc.).
- HTTP handlers with the real router, JSON parsing, serialization.
- Message consumers end-to-end against a real broker instance.
- Multi-module workflows: "when A publishes, B consumes and writes to
  C".

### End-to-end

- Critical user journeys: sign in, checkout, publish a post.
- Contract with the real browser (Playwright).
- NOT used for validating every business rule; it's coverage of the
  *plumbing*.

## Contract tests

When you have multiple services or a client/server pair, contract
tests prevent "works on my service, breaks on yours" drift.

- **Consumer-driven** (Pact) — consumer defines what it expects;
  provider verifies. Shared contract as source of truth.
- **Provider-driven** (OpenAPI) — provider publishes spec; consumers
  validate their usage.

Use when:

- Two teams own the consumer and provider.
- The provider's API evolves faster than full e2e tests can cover.

## Integration test infrastructure

**TestContainers** (Java, Python, Node, Go, Rust, C#, Ruby) — starts
real Postgres / Kafka / Redis in Docker for the duration of the
test / session.

```python
# Python
from testcontainers.postgres import PostgresContainer

@pytest.fixture(scope="session")
def pg() -> Generator[str, None, None]:
    with PostgresContainer("postgres:16") as c:
        yield c.get_connection_url()
```

Pros: real behavior, no mocks, portable, works in CI.
Cons: Docker required; a few seconds per session to start.

Alternatives:

- **In-memory fakes** (H2 instead of Postgres) — avoid. Subtle
  divergences in SQL semantics bite.
- **SQLite in memory for a Postgres app** — also avoid. Same reason.
- **Shared dev DB** — don't. Flakes from parallelism, data leak
  across tests.

## Snapshot / golden file tests

- Good for: serialized output (JSON responses, generated code,
  rendered templates, OpenAPI specs).
- Bad for: anything with timestamps, random IDs, set-ordering.

Normalize first. Store snapshots in git. Review diffs in PR — a
changed snapshot is a real assertion that needs a human to look.

Tools: `syrupy` (Python), `jest --snapshot`, `insta` (Rust).

## Test pyramid metrics

What to track per suite:

- **Count** per level.
- **Total duration** per level.
- **Flake rate** per level. Target < 0.1% for unit, < 1% for
  integration, acknowledge higher for e2e but ratchet down.
- **Failed-per-merge rate**.

Re-balance when numbers drift.

## Avoiding the "ice-cream cone"

```
   ------
    E2E      (many, slow, flaky)
   ------
    unit     (few, nominal)
   ------
```

Symptoms:

- Teams write e2e because it "covers everything".
- Unit tests are shallow — only testing getters/setters.
- CI takes 45 minutes and is red half the time.

Fix:

- Pick a critical business rule.
- Ask: can it be tested at unit level with real collaborators?
- If yes, write that test, then delete the equivalent e2e.
- Repeat.

## Coverage rules

- **Report line + branch coverage** as separate metrics.
- **Exclude generated code, migrations, `__main__`** — they're not
  code you test.
- **Treat the coverage report as a map**, not a scoreboard. Find
  untested branches → decide: test it, or document why not.
- **80% for application code** is a reasonable floor. Below that,
  uncovered paths accumulate bugs.
- **100% on safety-critical code** (payments, auth, data integrity),
  augmented with mutation testing.
- **Don't gate PRs on coverage deltas without context** — chasing
  numbers encourages bad tests.

## Test ownership

Tests live **next to the code they test**, in the same language /
repo. Assigning "the QA team" ownership of the unit suite is an
organizational anti-pattern — devs must own their tests.

QA-style teams work best on:

- Exploratory testing.
- Chaos / load / security scenarios.
- End-to-end journey definitions.
