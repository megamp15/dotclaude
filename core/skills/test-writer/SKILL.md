---
name: test-writer
description: Write comprehensive tests for new or changed code. Maps code paths (happy, edge, error), writes one test per scenario with arrange-act-assert. Can auto-trigger on new features.
source: core
triggers: /test-writer, write tests for, add tests, test coverage, after adding a feature
---

# test-writer

Produce a thorough, readable test file for a unit of code. Works best on
a single module, class, or function at a time.

## Workflow

### 1. Understand the target

- Read the code being tested.
- Identify the **public surface** — what do callers actually use?
- List the **inputs and outputs** for each public function.
- Identify **side effects** — DB writes, network calls, filesystem, clock, randomness.

### 2. Map the paths

For each public function, list:

- **Happy path** — one or two typical inputs.
- **Edge cases** — empty, single, many, max size, boundary values, unicode, whitespace, negative, zero, very small, very large.
- **Error cases** — invalid type, invalid value, dependency failure, timeout, cancellation.
- **Concurrency** — if the code is async or threaded, what races are possible?
- **State-dependent** — behavior that differs based on prior calls or external state.

Don't write any tests yet. Complete the map first.

### 3. Pick the framework

Use what the project already uses. If multiple are configured, use the most recent in the test directory. If the project has no tests yet, pick the stack-standard (`pytest` for Python, `vitest`/`jest` for JS/TS, `go test` for Go, etc.).

### 4. Write the tests

For each scenario from the map, one test:

- **Name:** describes the scenario in plain language. `test_returns_empty_list_when_input_is_none`, `test_rejects_amount_greater_than_balance`.
- **Structure:** Arrange / Act / Assert, separated by blank lines.
- **Single behavior:** one logical thing per test. Multiple `expect` calls on the same act are fine.
- **Parametrize** for the same logic across inputs — don't copy-paste.

### 5. Mock only at boundaries

- Network, filesystem, DB, time, randomness — mock these.
- Pure logic — don't mock. Use real values.
- Don't mock what you don't own — wrap it in an adapter and mock the adapter.
- Prefer fakes (in-memory implementations) over mocks where it makes sense.

### 6. Verify

- Run the new tests: pass.
- Run one at a time via `grep`-style filter to confirm each actually exercises what it claims.
- Mutate the production code (temporarily) to confirm the tests catch the mutation. If a test still passes after you break the code, it's not testing what it claims.
- Restore the code. Tests should be green.

### 7. Report

- Scenarios covered, grouped by function.
- Any scenarios intentionally skipped (and why).
- Coverage delta if the project tracks it.
- Any additional test files or fixtures added.

## Quality bar

Every test should:

- **Fail** if the production code is wrong.
- **Pass** if the production code is right.
- **Not change** when unrelated production code refactors.
- **Read** like a spec to someone who's never seen the code.

## Anti-patterns

- **Coverage-driven tests.** Hitting a line is not the same as testing its behavior.
- **Implementation tests.** Asserting that a private method was called, or that a specific algorithm was used.
- **`assert x is not None`** as the only assertion. Tells you the function ran, not that it worked.
- **Tests that share mutable state.** Order-dependent tests are broken tests.
- **Sleep-based synchronization.** Use polls with timeouts, or mockable clocks.
- **One monster test.** If a test needs 30 lines of setup and 5 assertions covering different behaviors, it's several tests.

## Auto-trigger behavior

This skill may be invoked automatically after:

- A commit adds a new public function, class, or module.
- A PR is opened with new untested code.
- The user asks "does this have tests?" and the answer is no.

When auto-triggering, always ask once — "I'd like to add tests for [X]. Proceed?" — before writing. Never surprise the user with new files.

## How to behave

- Use the same test style, helpers, and fixtures that already exist in the suite.
- Keep test files flat and discoverable. One test file per production file is a good default.
- Don't refactor the code being tested. If it's hard to test, say so and suggest a refactor as a follow-up.
