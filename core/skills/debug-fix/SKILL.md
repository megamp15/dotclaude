---
name: debug-fix
description: Find and fix a bug methodically — reproduce, isolate root cause, minimal fix, regression test, commit. Use for issue numbers, error messages, or verbal bug descriptions.
source: core
triggers: /debug-fix, debug this, find the bug, fix this error, reproduce issue, regression
---

# debug-fix

A discipline for fixing bugs without making the code worse. The bug is
not fixed until a test guards against its return.

## Workflow

### 1. Understand the bug

Ingest whatever the user provides:

- Issue number → read via `gh issue view <n>` (or the project's tracker).
- Error message → locate its source (search literal, then regex).
- Verbal description → restate in your own words; get confirmation if anything is ambiguous.

Before writing any code, state:

- **Expected:** what should happen.
- **Actual:** what's happening.
- **When:** the conditions that trigger it.

If you can't articulate these, you don't understand the bug yet — ask.

### 2. Reproduce

A bug you can't reproduce is a bug you can't verify you fixed.

- Find or write the minimum reproduction — inputs + steps that reliably trigger the bug.
- Reproduce in a test (even a failing one with `@pytest.mark.xfail`) when possible.
- If the bug is intermittent, run the repro many times to bound its rate.

If reproduction is impossible in the current environment, say so and stop. Guessing at a fix without repro is how regressions happen.

### 3. Isolate the root cause

Not the symptom. Not the first plausible line. The root cause.

- Work backwards from the symptom. `git log` and `git blame` on the suspect lines.
- Bisect if the bug appeared recently (`git bisect`).
- Add logging or use a debugger — don't squint at code for longer than 10 minutes without instrumentation.
- State the root cause in one sentence before fixing: "this breaks because [X] happens when [Y], and the code assumes [Z]".

### 4. Make the minimal fix

- Change the smallest set of lines that addresses the root cause.
- Do **not** refactor surrounding code in the same change. If the code around the bug needs work, that's a separate commit.
- If the fix requires touching many places, the root cause may be a missing abstraction. Say so; discuss before sprawling the fix.

### 5. Write the regression test

A test that:

- Fails on the pre-fix code.
- Passes on the post-fix code.
- Has a name that describes the bug ("does not drop events when queue overflows", not "test_bug_134").

If you wrote the repro as a test in step 2, promote it now.

### 6. Verify

- Run the regression test: passes.
- Run the whole suite: no new failures.
- Run the linter and type-checker if they're part of the project's flow.

### 7. Commit

Message subject: describe the bug that was fixed.

> `Fix: Queue drops events when full instead of applying backpressure`

Body: restate expected/actual/root cause from step 1, reference the issue.

### 8. Report

Summarize:

- What was broken and why.
- What the fix does.
- Scope of the change (files, lines).
- Any follow-ups you noticed but didn't do (separate issues).

## Do not

- Fix symptoms. If the error was "undefined", find out why it's undefined — don't add an `|| {}`.
- Change error messages to silence a failing test.
- Add a catch-all `try/except` to make the stack trace go away.
- Merge the fix with an unrelated refactor.
- Declare "fixed" without running the test suite.

## Reference

| Topic | Reference |
|---|---|
| Common bug archetypes and their root causes | `references/bug-archetypes.md` |
| Bisecting & instrumentation | `references/isolation.md` |
