# Errors

Go's error model has converged on a clear set of patterns since 1.13. The
only valid styles for new code are: sentinel errors (rare, exported),
typed errors (libraries with structured failure modes), and wrapped errors
(everywhere else).

## Wrapping with `%w`

Always wrap unless the immediate caller is the layer that logs and stops:

```go
if err := db.Insert(row); err != nil {
    return fmt.Errorf("insert user %q: %w", row.ID, err)
}
```

Use `%w` (not `%v` / `%s`) when wrapping. `%w` makes the original error
accessible through `errors.Is` and `errors.Unwrap`. Use `%v` only when
you intentionally don't want the chain — rare.

The wrapping message is **what this layer was doing**, not a restating of
the inner error. Bad: `"insert user: failed to insert user"`. Good:
`"insert user %q during signup": %w`.

## Comparing errors

Never compare with `==` (except `io.EOF` and similarly documented sentinels
that are explicitly returned unwrapped). Always:

```go
if errors.Is(err, sql.ErrNoRows) { … }

var pathErr *fs.PathError
if errors.As(err, &pathErr) {
    log.Printf("path %q failed: %v", pathErr.Path, pathErr.Err)
}
```

`errors.Is` walks the chain looking for matches. `errors.As` walks the
chain looking for a type-assertable match and assigns to the target.

## Sentinel errors

Reserved for cases where callers genuinely need to recognize a specific
condition without inspecting structured data:

```go
package store

var (
    ErrNotFound = errors.New("not found")
    ErrConflict = errors.New("conflict")
)
```

Use sparingly — sentinels create coupling. Prefer typed errors when the
caller might want context (which row, which constraint).

Document that the sentinel is returned wrapped (`fmt.Errorf("…: %w",
ErrNotFound)`). Callers must use `errors.Is`, not `==`.

## Typed errors (the library default)

When the caller needs structured information about the failure:

```go
type ValidationError struct {
    Field   string
    Reason  string
}

func (e *ValidationError) Error() string {
    return fmt.Sprintf("validation: field %q: %s", e.Field, e.Reason)
}
```

Optionally implement `Unwrap()` if your error wraps an inner cause, and
`Is()` if there's an equivalence relation:

```go
func (e *ValidationError) Is(target error) bool {
    var t *ValidationError
    if !errors.As(target, &t) { return false }
    return e.Field == t.Field
}
```

Pointer receivers on the error methods: callers `errors.As(err,
&validationErr)` get a `*ValidationError`. Returning the value type is
fine; just be consistent.

## `errors.Join` for aggregation

When parallel work returns multiple errors and you want all of them:

```go
var errs []error
for _, item := range items {
    if err := process(item); err != nil {
        errs = append(errs, fmt.Errorf("item %s: %w", item.ID, err))
    }
}
if len(errs) > 0 {
    return errors.Join(errs...)
}
```

`errors.Is`/`errors.As` walk *all* joined errors. `Error()` returns each
on a new line. Useful for batch operations and validation results.

`errgroup.Group` returns only the first error. Use `errgroup` when
short-circuiting is right; use `errors.Join` when you want to collect
everything.

## When to panic

Panics are for **unrecoverable programmer errors** that should be caught
during development:

- Indexing past the end of a known-bounded array because of a logic bug.
- A `default:` in a switch that should be exhaustive.
- A nil receiver in a method that documents non-nil.

Never panic on caller input. Public functions return `error`. Library
code that panics on user data is broken.

If you must `recover()` (e.g., HTTP handler middleware), do it at one
defined boundary, log with stack trace, and convert to a 500. Don't
sprinkle `recover()` calls.

## Errors at boundaries

The pattern that scales:

- **Internal layers wrap and return.** Each layer adds context.
- **The outermost layer (HTTP handler, CLI command, job worker) logs once
  and converts to the user-facing error.**
- **Logs are structured.** `slog.Error("op failed", "op", "create_user",
  "err", err)`. Don't log mid-stack and re-wrap; you'll log the same chain
  multiple times.

For HTTP, map known errors to status codes at the boundary:

```go
switch {
case errors.Is(err, store.ErrNotFound):
    http.Error(w, "not found", http.StatusNotFound)
case errors.Is(err, ErrUnauthorized):
    http.Error(w, "unauthorized", http.StatusUnauthorized)
default:
    log.Error("internal", "err", err)
    http.Error(w, "internal error", http.StatusInternalServerError)
}
```

Don't expose internal error messages to users — that's an information leak.
Log them, return generic messages.

## Anti-patterns

- **`if err != nil { return err }` everywhere.** You lose the call chain.
  Wrap with context.
- **`fmt.Errorf("...: %v", err)`** when you mean wrap. Use `%w`.
- **`errors.New("error: ...")`** — start the message with what you were
  doing, not the word "error". The error is already an error.
- **Capitalizing error messages.** `errors.New("not found")`, not `"Not
  found"`. They concatenate into longer messages.
- **Trailing newlines / punctuation in error messages.** They concatenate
  poorly. End with a noun phrase, no punctuation.
- **`errors.Is(err, nil)`** to mean "no error" — just `err == nil`.
- **Recovering panics broadly to "make code more robust".** Hides bugs.
  Recover only at one logged boundary.
- **Returning a typed error as `error` interface but still expecting `==`
  to work.** Use `errors.As`.
