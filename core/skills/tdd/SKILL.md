---
name: tdd
description: Strict red-green-refactor TDD loop for a feature or function. One failing test → minimum code to pass → refactor → commit. Works simple-to-complex.
source: core
triggers: /tdd, tdd this, test-driven, write failing test first, red green refactor
---

# tdd

Strict Test-Driven Development. You do not write production code except to
make a failing test pass.

## The loop

```
1. RED     — write one failing test
2. GREEN   — minimum code to pass it (ugly is fine)
3. REFACTOR — clean up without changing behavior
4. COMMIT  — one commit per green+refactor cycle
5. Go to 1
```

## Progression order

Walk up the complexity ladder:

1. **Degenerate cases** — empty input, null, zero, default.
2. **Happy path** — a single typical input.
3. **Variations** — a few realistic cases that exercise different branches.
4. **Edge cases** — max size, unicode, boundary values, precision.
5. **Error cases** — invalid input, missing dependency, timeout.
6. **Integration** — only after the unit behavior is solid.

Don't write the whole test file up front. One test at a time.

## Rules

### Red step
- Test fails **for the reason you expect**. If it fails for the wrong reason, the test is wrong — fix the test, not the production code.
- Name the test for the scenario: `test_returns_zero_when_list_is_empty`, not `test_sum`.
- No multiple assertions that cover unrelated scenarios. Split them.

### Green step
- Write the **minimum** to pass. `return 0` is a legitimate first implementation.
- No speculative generality. No "I'll need this later".
- It's OK to write ugly code here. Refactor step cleans it.
- If you can't make the test pass with a minimum change, the test was too big — back up and split.

### Refactor step
- **No new behavior** in this step. Only behavior-preserving changes.
- All tests must stay green at every step of the refactor — run the suite.
- If a refactor gets big, it's not part of this cycle. Stop, commit what's green, start a new cycle.

### Commit step
- Commit after each green+refactor cycle. Messages like `Add test: empty list returns zero` → `Implement: sum of list` → `Refactor: extract accumulator`.
- Don't commit red. Don't commit during a half-done refactor.

## What TDD gives you

- A reason to stop — each passing test proves progress.
- A safety net — the next refactor is cheap because tests catch regressions.
- Smaller, testable interfaces — because you designed from the caller's side.

## What TDD does NOT give you

- The right architecture. You can TDD yourself into the wrong design. Step back between cycles and ask "is this still the right shape?"
- 100% coverage as a goal. Coverage is a side effect, not the target.
- An excuse to skip integration testing. TDD is for the unit; integration needs its own story.

## When TDD is the wrong tool

- Spiking / exploring — throw away the spike, then TDD the real implementation.
- Pure UI / visual work where the assertion would be "looks right".
- Performance-critical optimization — measure first, then test for the improvement.

## How to behave

- Ask what behavior to test first if the user hasn't specified.
- After each cycle, show the diff and the test result before moving on.
- If the user says "just write it" — stop TDD, switch to a regular implementation + tests-after approach. Don't secretly abandon the loop.
