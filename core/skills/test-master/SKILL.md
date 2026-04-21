---
name: test-master
description: Testing strategy and craft — pyramid shape, classical vs. mockist style, property-based testing, mutation testing, contract tests, integration vs. unit boundaries, test data strategy, and patterns for fast + deterministic suites. Complements `core/skills/test-writer` (tactical scaffolding) and `core/skills/tdd` (workflow).
source: core
triggers: /test-master, testing strategy, test pyramid, flaky tests, mutation testing, property-based testing, contract testing, test doubles, integration test, unit test, golden file, snapshot, TestContainers, mock vs fake, test data builders, deterministic tests
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/test-master
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# test-master

Deep testing expertise. Activates when the question is about test
**strategy** — what to test, at what level, how to make it fast and
deterministic — not "write me a unit test".

> **See also:**
>
> - `core/skills/test-writer/` — tactical test scaffolding
> - `core/skills/tdd/` — TDD workflow
> - `core/skills/playwright-expert/` — browser end-to-end
> - `stacks/python/skills/python-pro/references/testing.md` — pytest
>   specifics
> - `core/rules/testing.md` — baseline conventions

## When to use this skill

- A suite is slow / flaky / expensive and you need to rearchitect it.
- Designing the test strategy for a new service.
- Deciding between unit / integration / e2e for a specific concern.
- Introducing mutation testing, property-based testing, or contract
  tests.
- Balancing test doubles (stub / fake / mock / spy).
- Building test data that survives refactors.

## References (load on demand)

- [`references/pyramid-and-strategy.md`](references/pyramid-and-strategy.md)
  — the pyramid, the honeycomb, the diamond — and when each fits.
  Classical vs. mockist. When integration tests pay off. What's
  actually worth an e2e.
- [`references/test-doubles.md`](references/test-doubles.md) — stub,
  fake, mock, spy, dummy — what each is for, when mocks turn into
  liabilities, fakes as investment, testing the boundary vs. the
  internals.
- [`references/property-and-mutation.md`](references/property-and-mutation.md)
  — property-based testing (Hypothesis / fast-check) patterns and
  shrinking; mutation testing (mutmut / Stryker / PIT) as coverage
  truth, picking hot paths to mutate.
- [`references/flaky-and-fast.md`](references/flaky-and-fast.md) —
  sources of flakes (time, randomness, concurrency, shared state,
  network, test order), TestContainers, the deterministic-clock
  pattern, parallelization, test impact analysis.

## Core workflow

1. **Ask what changes most often, and make the tests at that level
   cheap.** If the domain logic changes daily, unit tests dominate.
   If the orchestration changes daily, integration tests dominate.
2. **Test behavior, not implementation.** A passing test after a
   refactor is a real test. A failing one after a harmless refactor
   is a liability.
3. **Fast suites earn trust.** Under 10 seconds for unit suite → devs
   run it. Over 2 minutes → they don't.
4. **Deterministic or delete.** A flaky test is worse than no test —
   it erodes trust in the whole suite.
5. **Coverage is a floor, not a goal.** Target line coverage of
   ~70–85% for library code; more isn't better past that.

## Defaults

| Question | Default |
|---|---|
| Test shape | Pyramid for domain-heavy services; honeycomb (fewer unit, more integration) for glue services |
| First choice of test double | Pass a real fake > pass a stub > inject a mock |
| New test | Start at the public API, not a private helper |
| Assertion style | Behavior-based (`result == expected`); avoid `verify(mock).calledWith(...)` when a state assertion would work |
| Test data | Builder / factory functions, not big fixture trees |
| External services in tests | TestContainers for DB/Kafka/Redis; HTTP mocking for third-party APIs |
| Determinism | Inject clock, random seed, IDs — never call `time.now()` directly in tests |
| Parallelization | On, `-n auto` / `xdist` / `maxWorkers`, unless tests genuinely can't share a DB |
| Coverage | 80% for app code; 100% on anything finance/security critical. Line + branch |
| Mutation score | 60%+ on critical modules, over time |
| Property-based tests | For parsers, serializers, invariant-heavy functions |

## Anti-patterns

- **"Happy path only" suites.** No negative tests = no tests.
- **Testing via mocks of your own classes.** If changing a private
  method breaks 30 tests, the tests are pinned to implementation.
- **Asserting on log output in production code tests.** Logs change;
  tests break; nobody fixes them meaningfully.
- **Giant fixtures loaded in every test.** Builder functions let each
  test say what it actually needs.
- **Tests that share state via a singleton / module-level DB
  connection.** Source of heisen-failures.
- **Skipped tests left in the suite.** Delete or fix; "skipped" rots.
- **`time.sleep()` or retry-until-passes.** Use explicit waits for
  conditions.
- **E2E tests covering business rules that unit tests could cover.**
  E2E is for integration, not for "the sum of two numbers".

## Output format

For a strategy review:

```
Current shape:     <unit / integration / e2e percentages>
Flake rate:        <X%>
Suite time (CI):   <N minutes>
Issues:            <top 3>

Recommendations (in order of ROI):
1. <biggest win — usually: determinism, parallelization, or pyramid rebalance>
2. ...
3. ...

Quick wins (this sprint):
- <1–3 concrete actions>

Bigger investments:
- <refactor / tooling>
```

For specific test-design questions:

```
Behavior under test:
  <one sentence>

Right level:
  unit | integration | e2e

Test double strategy:
  <real / fake / stub / mock>

Assertion:
  <what you check>

Non-goals:
  <what this test deliberately doesn't cover>
```
