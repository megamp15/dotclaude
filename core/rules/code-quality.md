---
name: code-quality
description: Universal code quality rules — naming, structure, comments, error handling
source: core
alwaysApply: true
---

# Code quality

Language-agnostic principles. Stack-specific rules refine these.

## Naming

- Names describe intent, not implementation. `retryCount` not `cnt`, `users` not `data`.
- Booleans read as predicates: `isValid`, `hasChildren`, `canEdit` — not `valid`, `children`, `edit`.
- Avoid abbreviations except for well-known ones (`url`, `id`, `db`, `api`).
- Avoid Hungarian notation and type suffixes (`usersList`, `configMap`). The type system shows the type.
- Functions are verb phrases (`fetchUser`, `validateInput`). Classes and types are noun phrases.
- No single-letter names except loop indices (`i`, `j`) and standard math (`x`, `y`).

## Structure

- Files do one thing. If a file has unrelated exports, split it.
- Functions do one thing. If the name contains "and", split it.
- Prefer early returns and guard clauses over nested `if`s.
- Keep functions under ~50 lines when possible. Over 100 is a smell.
- Module boundaries should be defensive; internal helpers don't need to be.

## Comments

- Explain **why**, not **what**. The code shows what.
- No narration (`// increment counter`, `# return result`).
- Document non-obvious trade-offs, constraints, invariants, and historical context ("kept for backward compat with X because Y").
- `TODO(owner): description` — include an owner handle so it's actionable.
- Remove commented-out code. Git remembers.

## Error handling

- Catch the narrowest exception type that makes sense. No bare `catch`.
- Never swallow errors silently. Log, rethrow, or handle — pick one and be explicit.
- Error messages include enough context to debug without adding logging later ("failed to fetch user 42 from users table" beats "fetch failed").
- Don't use exceptions for control flow in hot paths.
- When you re-raise, preserve the stack trace (`raise` in Python, `throw` in JS with the original error).

## State & mutation

- Prefer immutable values and pure functions where practical.
- If mutation is required, constrain its scope — short-lived local state is fine, leaking it is not.
- Never share mutable state across threads/async boundaries without a lock or explicit protocol.
- Avoid global mutable state. If you think you need it, you probably want dependency injection.

## Duplication

- Three occurrences is the threshold for extracting a helper, not two. Premature abstraction is worse than duplication.
- Different code that looks similar is not the same code. Don't force a shared abstraction over coincidental similarity.

## Dead code

- No unused imports, variables, parameters, private methods.
- No unreachable branches. If a branch is defensive for an "impossible" case, explain why in a comment.
- No feature flags that have fully rolled out. Delete them.
