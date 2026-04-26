---
name: testing
description: Testing hub with three modes: tdd (red-green-refactor workflow), write (add tests for code), and strategy (suite architecture, flakiness, doubles, property/mutation/contract tests). Replaces tdd, test-writer, and test-master as one top-level skill.
source: core
triggers: /testing, /tdd, tdd this, test-driven, red green refactor, write tests, add tests, test coverage, testing strategy, test pyramid, flaky tests, mutation testing, property-based testing, contract testing, test doubles, integration test, unit test, golden file, snapshot, TestContainers, deterministic tests
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/test-master
ported-at: 2026-04-17
adapted: true
---

# testing

One skill, three modes. Choose the mode by the user's intent:

| Signal | Mode |
|---|---|
| "TDD this", "write failing test first", feature not implemented yet | `tdd` |
| "Add tests for X", changed code needs coverage, module/class/function target | `write` |
| Suite shape, flakiness, test doubles, property/mutation/contract testing | `strategy` |

## Shared rules

- Test behavior, not implementation.
- Prefer the project's existing test framework, naming style, fixtures, and
  helpers.
- One scenario per test unless parametrization expresses the same behavior.
- Mock only at boundaries: network, filesystem, DB, time, randomness, external
  services. Prefer fakes when they make the tests clearer.
- A test is not done until it fails when the behavior is broken and passes when
  the behavior is correct.

## Mode: tdd

Use when the user wants red-green-refactor discipline.

Loop:

```text
1. RED: write one failing test.
2. GREEN: make the minimum production change to pass.
3. REFACTOR: clean up without changing behavior.
4. VERIFY: run the focused test, then the relevant suite.
5. COMMIT or report the cycle, depending on the user's workflow.
```

Progress from degenerate cases, to happy path, to variations, to edge cases,
to error cases, then integration. Do not write the whole test file up front.
If the user says "just write it", switch to implementation plus tests-after.

## Mode: write

Use when code already exists and needs tests.

Workflow:

1. Read the public surface and side effects.
2. Map happy, edge, error, concurrency, and state-dependent paths.
3. Pick the local framework and style.
4. Write one readable test per scenario.
5. Verify the new tests and, where practical, mutate the production code
   temporarily to prove the tests catch real failures.
6. Restore code and report covered and intentionally skipped scenarios.

## Mode: strategy

Use for suite architecture and testing craft.

Strategy-mode references (load on demand):

- [`references/strategy-pyramid.md`](references/strategy-pyramid.md) for
  level selection and suite shape.
- [`references/strategy-test-doubles.md`](references/strategy-test-doubles.md)
  for stubs, fakes, mocks, spies, and boundary strategy.
- [`references/strategy-property-and-mutation.md`](references/strategy-property-and-mutation.md)
  for Hypothesis, fast-check, mutmut, Stryker, PIT, and invariant testing.
- [`references/strategy-flaky-and-fast.md`](references/strategy-flaky-and-fast.md)
  for deterministic clocks, shared state, test order, parallelization, and
  CI speed.

Output for strategy reviews:

```text
Current shape:     <unit / integration / e2e mix>
Suite time:        <local and CI if known>
Top risks:         <flake, slowness, low signal, missing level>

Recommendations:
1. <highest ROI change>
2. ...

Quick wins:
- <small changes this sprint>

Bigger investments:
- <tooling or refactor>
```

