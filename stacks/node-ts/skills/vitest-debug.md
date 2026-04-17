---
name: vitest-debug
description: Investigate and fix a failing Vitest or Jest test with a tight reproduce-isolate-fix loop
source: stacks/node-ts
---

# Vitest / Jest debugging

Use when: a test is failing and the cause isn't obvious from the output.
Works for Vitest and Jest — their CLIs and error output are close enough
that the same moves apply.

## Loop

### 1. Run just the failing test

```
pnpm vitest run path/to/file.test.ts -t "test name fragment"
# or
pnpm jest path/to/file.test.ts -t "test name fragment"
```

Don't run the whole suite while debugging one. Fast iteration matters.
Add `--reporter=verbose` (Vitest) / `--verbose` (Jest) for full output.

### 2. Read the error properly

- **Assertion failure:** `expected / actual` — read both carefully. Types matter (`1 !== "1"`).
- **Thrown in test:** is it during setup (`beforeEach`), the act, or cleanup (`afterEach`)? Location differs.
- **`Cannot find module`:** path or alias resolution issue. Check `tsconfig.json#paths` and vitest/jest config.
- **`is not a function`:** default vs named import mismatch, or a mock overwrote the real export with `undefined`.
- **Timeout:** the test awaited something that never resolves. More common than test logic bugs.

### 3. Check assumptions one at a time

Before changing code, verify each assumption with a focused probe:

```ts
it("debug", () => {
  const result = subject.method(input);
  console.log("probe:", result);           // visible with --reporter=verbose
  expect(result).toBeDefined();
});
```

Or: `--inspect-brk` + a debugger.

### 4. Common failure modes

#### Async not awaited

```ts
// BUG: returns before expectation runs
it("fails silently", () => {
  fetchThing().then(t => expect(t).toBe(42));
});

// FIX: await, or return the promise
it("fixed", async () => {
  const t = await fetchThing();
  expect(t).toBe(42);
});
```

`no-floating-promises` ESLint rule catches most of these. Turn it on.

#### Timer / clock issues

- Code uses `setTimeout`, `setInterval`, or `Date.now()` → use fake timers.

```ts
import { vi } from "vitest";  // or jest
beforeEach(() => vi.useFakeTimers());
afterEach(() => vi.useRealTimers());

it("fires after delay", () => {
  const cb = vi.fn();
  scheduleThing(cb);
  vi.advanceTimersByTime(1000);
  expect(cb).toHaveBeenCalled();
});
```

#### Test pollution

Symptoms: test passes in isolation, fails as part of the suite; or order-dependent.

Causes:
- Module-level state (singletons, caches, `let` at module top).
- Shared mocks not cleared. Use `vi.clearAllMocks()` / `jest.clearAllMocks()` in `beforeEach`.
- Real DB/FS side effects not rolled back.

Run with `--isolate` to force process isolation if you suspect globals.

#### Mock confusion

- **`vi.mock()` / `jest.mock()` is hoisted** to the top of the file. Don't put runtime variables in the factory — they won't exist yet.
- **`vi.doMock()` / `jest.doMock()`** is not hoisted; use this when you need a runtime value in the mock.
- **ESM + Vitest:** mocking side-effect imports sometimes requires `vi.hoisted()` for variables.
- **`vi.spyOn(obj, "method")`** is preferable when you only want to observe calls without changing behavior. Remember to restore.

#### Snapshot drift

- Intentional change → `--update` (`-u`).
- Unintentional change → the output *is* drifting; investigate why before updating.
- Never blindly update snapshots when you don't understand what changed.

### 5. Minimal fix

Once you've isolated the cause, the fix is usually one of:

- Await the missing promise.
- Clear a shared mock in `beforeEach`.
- Fix a module-level leak.
- Use fake timers / real timers correctly.
- Correct the assertion that was wrong.

If the "fix" requires restructuring the production code under test and you didn't expect to, stop and reconsider — the test may be telling you about a real design issue, not just a test issue.

### 6. Run the full suite

Before committing: run the full test suite, not just the repaired one. A
fix to shared setup can break other tests.

```
pnpm vitest run
# or
pnpm jest
```

## Anti-patterns

- `it.only` committed to main.
- `it.skip` with no TODO comment explaining why.
- "Fixed" by loosening the assertion (`.toBe(42)` → `.toBeDefined()`). That's hiding the bug.
- Increasing a timeout to "fix" flakiness without investigating *why* the test was slow.
- Mocking the thing you're supposedly testing.
