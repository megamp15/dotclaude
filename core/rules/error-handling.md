---
name: error-handling
description: Universal error-handling patterns — where to catch, what to re-raise, how to fail loud
source: core
alwaysApply: true
---

# Error handling

Language-agnostic. Stack rules refine with specific APIs (`try/except`,
`try/catch`, `Result<T,E>`, etc.).

## Where to handle errors

Three layers matter:

1. **Origin** — the call that can fail. Do the smallest thing you can do here: retry if transient, return an explicit error if expected, let it propagate otherwise.
2. **Boundary** — API entry, queue consumer, CLI main, scheduled job. Translate internal errors into something the caller understands and can act on. This is where you log with full context.
3. **Outermost** — top-level handler. Catch-all that prevents a crash, logs, returns a generic failure to the user. Must never be the *only* handler.

Handling in the middle of the stack is usually wrong. If a function can't do anything useful with the error, don't catch it.

## What "handle" means

- **Retry** — the error is transient (network blip, rate limit, lock timeout). Bounded retries with backoff. Not infinite.
- **Recover** — there's a defined fallback (use cache, use default value, skip this item, degrade gracefully).
- **Translate** — re-raise as a different error type that the layer above understands (`DBConnectionError` → `ServiceUnavailable`).
- **Record + rethrow** — log with context, then let it propagate. Useful at boundaries.
- **Fail** — unrecoverable; surface the error. This is the default.

"Swallow and continue" is **not** handling. It hides bugs.

## What to never do

- **Bare catch-all** (`except:`, `catch(Throwable)`, `catch { }`) — you lose the type and the cause. Always narrow.
- **Swallow silently.** `try { ... } catch (e) {}` is almost always a bug. If the error is expected and ignorable, log it and say why.
- **Mask the original cause.** When translating, preserve the original — `raise NewError(...) from original` in Python, `new Error(msg, { cause: original })` in modern JS, `fmt.Errorf("...: %w", err)` in Go.
- **Return None/null/undefined to signal error** in new code. Use `Result`, optional types, or exceptions depending on language. Silent `None` returns at one layer become crashes three layers up.
- **Use exceptions for control flow.** Throwing to short-circuit a loop is abuse. Use `return`/`break`/a sentinel.
- **Log and rethrow at every layer.** You'll have the same error logged 8 times. Log once, at the boundary that handled it.

## Error messages

Every message should include enough context that a debugger doesn't need to add logging to investigate:

- **What** operation failed (`failed to fetch user`).
- **Which** entity (`user id=42`).
- **Why** if known (`timeout after 5s`).
- **Where** (filename/function in stack, usually automatic).

Bad: `"operation failed"`.
Good: `"failed to fetch user id=42 from users table: timeout after 5s"`.

## Error types

- Invent domain-specific error types where they help the caller distinguish handling. (`NotFoundError` vs `ValidationError` vs `PermissionError` — the API layer maps each to a different HTTP code.)
- Don't invent one per call site. Two dozen exception classes for one module is a smell.
- Inherit from a base for your domain (`class MyServiceError(Exception)`) so callers can catch broadly when that's right.

## Retries

- Only retry **idempotent** operations. If retrying might double-charge, don't.
- Bounded attempts (3 is a reasonable default) with backoff (exponential, jittered).
- Retry on specific error classes (network, 5xx, rate limit), not everything.
- After the final failure, surface the original error with attempt count.
- Know what the caller expects — retrying silently for 30s when the caller needs an answer in 500ms is worse than failing fast.

## Timeouts

- Every external call has a timeout. The default is "never" in most libraries — override.
- Timeouts shorter than the caller's timeout. Otherwise you hold the caller's budget hostage.
- Distinguish connect timeout from read timeout when your library allows.

## Fail fast

- Validate inputs at the top of a function. Exit early with a clear error.
- Don't let invalid state propagate — bugs found near the origin are cheap; bugs found three layers deep are expensive.
- "Defensive programming" in the middle of the stack usually just moves the bug.

## Cleanup

- Every `open`/`acquire`/`start` has a matching `close`/`release`/`stop`, even on exception paths. Use context managers / `defer` / `try-finally` / `using`.
- Don't rely on garbage collection to close sockets, files, or transactions.
- Cleanup order is reverse of acquisition.
