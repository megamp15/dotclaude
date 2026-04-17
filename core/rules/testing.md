---
name: testing
description: Universal testing principles — what to test, how to name, what to avoid
source: core
alwaysApply: true
---

# Testing

Framework-agnostic. Stack rules pick the runner (`pytest`, `vitest`, `go test`, etc.).

## What to test

- Every public function/method with non-trivial behavior.
- Every bug fix gets a regression test that fails before the fix, passes after.
- Every branch in non-trivial control flow (error paths, early returns, edge cases).
- Every integration point (DB, external API, filesystem) through a contract test.

## What NOT to test

- Framework internals, third-party libraries, and language features.
- Trivial getters/setters and one-line delegations.
- Implementation details — test behavior at the boundary, not the internals. Tests that break on refactors that preserve behavior are testing the wrong thing.

## Test shape

- **Arrange / Act / Assert** (or **Given / When / Then**). Don't interleave setup and assertion.
- One logical assertion per test. Multiple related `expect` calls on the same object are fine; unrelated ones mean you have multiple tests.
- Use parametrization (`@pytest.mark.parametrize`, `test.each`, table tests) for the same logic across inputs. Never copy-paste a test with different numbers.
- Tests must be independent — any test should pass on its own, in any order, with any subset.

## Test names

- Describe the scenario, not the function. `test_rejects_negative_amounts` beats `test_validate`.
- Reads as a sentence: "test that [subject] [does thing] when [condition]".
- Group related tests in a class/describe block with a shared subject.

## Fixtures & mocks

- Prefer real values over mocks for pure logic. Mock only at I/O boundaries (network, FS, time, randomness).
- Don't mock what you don't own — mock a thin adapter around it instead.
- Fixtures should be obvious. If a test's setup is opaque, the test is a debugging puzzle for whoever reads it next.
- Avoid `session` / global fixtures unless there's a measurable perf reason. Shared state bites.

## Coverage

- Coverage is a smoke alarm, not a scorecard. 100% coverage with shallow assertions is worse than 80% with good ones.
- New code should be at least as well-covered as the module average.
- Lines not worth testing (`__repr__`, trivial DTOs) are explicit `# pragma: no cover`, not silently uncovered.

## Flakiness

- Flaky tests are broken tests. Fix or delete; don't retry-until-green.
- Common causes: time, randomness, network, shared global state, unordered collections, filesystem race conditions.
- Use injected clocks, seeded randomness, and explicit sorting. Never `sleep()` your way out of a race.

## Speed

- Unit tests under 100ms each. A suite over 60s means the wrong things are being integration-tested.
- Integration tests run separately (`-m integration`, `--run-integration`). CI runs both; local runs unit-only by default.

## Never

- Delete a failing test to "fix" the build without understanding what it was guarding.
- Weaken an assertion to make a test pass (`assertTrue(True)`, `expect(x).toBeDefined()` when the original checked a value).
- Commit a test marked `skip` or `xfail` without a linked issue explaining when and why it's expected to be re-enabled.
