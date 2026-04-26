---
name: go-engineer
description: Production Go expertise — package design, error wrapping with `errors.Is/As`, concurrency (goroutines, channels, errgroup, context), interfaces accepted but concrete returned, generics with type parameters, table tests, race detector, and modules/workspaces. Extends `stacks/lang/go/CLAUDE.stack.md` with design guidance and failure modes.
source: stacks/lang/go
triggers: /go-engineer, golang, go test, gofmt, gofumpt, goroutine, channel, context.Context, go module, go workspace, table test, interface design, error wrapping, errors.Is, errors.As, errgroup, sync.Mutex, race detector, generics, type parameters, go vet, staticcheck
---

# go-engineer

Idiomatic Go for people who already know the language. Activates when the
question is past style — "should this be an interface", "why is this race
detector flag firing", "how do I structure errors for this library", "what's
the right way to fan-out and aggregate results".

> **See also:**
>
> - `stacks/lang/go/CLAUDE.stack.md` — baseline conventions
> - `stacks/lang/go/rules/go-style.md` — enforceable rules
> - `core/skills/architect/` — for "how should I structure this service"

## When to use this skill

- Designing a public package API and choosing where interfaces live.
- Picking between sentinel errors, typed errors, and wrapped errors.
- Diagnosing a goroutine leak, deadlock, or data race.
- Choosing between channels, mutexes, sync.Map, atomic, and singleflight.
- Adding generics — and knowing when *not* to.
- Setting up a multi-module workspace or vendoring decision.
- Writing table tests that don't get unwieldy.

## References (load on demand)

- [`references/concurrency.md`](references/concurrency.md) — goroutine
  lifecycle, `context.Context` propagation, channel patterns (fan-in/fan-out,
  pipelines, semaphores), `errgroup`, `singleflight`, race detector, common
  leak shapes.
- [`references/errors.md`](references/errors.md) — sentinel vs. typed vs.
  wrapped, `errors.Is` / `errors.As`, `%w` formatting, when to panic, custom
  error types with structured context, `errors.Join` for aggregation.
- [`references/interfaces-and-generics.md`](references/interfaces-and-generics.md)
  — accept interfaces / return concrete, where interfaces should live, when
  to reach for type parameters, constraints, and the readability ceiling.
- [`references/testing.md`](references/testing.md) — table tests with
  `t.Run` subtests, `t.Cleanup`, golden files, fuzz tests, `httptest`,
  `testing/iotest`, race-flag CI hygiene, `testify` opinions.
- [`references/modules-and-tooling.md`](references/modules-and-tooling.md) —
  `go.mod` shape, `go work` workspaces, `replace` directives, build tags,
  `go vet`, `staticcheck`, `gofumpt`, `golangci-lint` config.

## Core workflow

1. **Classify the question** — concurrency / errors / interfaces / generics
   / testing / tooling. Load the relevant reference instead of guessing.
2. **Check the package boundary** — most Go bugs are wrong-package bugs.
   Where does this type live, who imports it, what's the consumer's view?
3. **Write the smallest reproducer** — a `_test.go` with `-race` is faster
   than reasoning about races in your head.
4. **Run the right verification** in this order, narrowing first:
   ```bash
   go test ./path/to/package -race -count=1
   go test ./... -race -count=1
   go vet ./...
   gofumpt -d <changed files>      # or gofmt
   golangci-lint run               # if configured
   ```
5. **Prefer stdlib** — `io`, `bufio`, `bytes`, `errors`, `slices`, `maps`,
   `cmp`, `context`, `sync`, `sync/atomic`, `testing/iotest`, `net/http`,
   `os/exec` cover most needs before reaching for a library.

## Defaults (fast decisions)

| Question | Default |
|---|---|
| Where does the interface live? | In the consumer package, not the producer's |
| Returning interface or concrete? | Return concrete; accept interfaces |
| Multiple goroutines that can fail | `errgroup.Group` (or `errgroup.WithContext`) |
| Bounded concurrency | `errgroup.SetLimit(N)` or buffered semaphore channel |
| Cache stampede / dedup in-flight calls | `golang.org/x/sync/singleflight` |
| Cancelable work | First param `ctx context.Context`; respect `ctx.Done()` |
| Wrapping errors | `fmt.Errorf("op X: %w", err)` — always `%w` for wrapping |
| Comparing errors | `errors.Is(err, target)`, not `==` |
| Library error type | Exported struct with `Unwrap()` and `Is()` methods |
| Tests with many cases | Table test with `tt.name` + `t.Run(tt.name, …)` |
| Test cleanup | `t.Cleanup(func(){ … })`, not `defer` |
| HTTP test | `httptest.NewServer` + real client, not a mock |
| Time in tests | Inject a clock; `time.Now()` in production is fine |
| Generics | Only when the alternative is unsafe or boilerplate-heavy |
| Module layout | `cmd/<binary>` + `internal/<pkg>`; add `pkg/` only when truly exported |
| Multi-module repo | `go.work` workspace, *not* `replace` directives in `go.mod` |

## Anti-patterns

- **Interface bloat in the producer package.** `type Storer interface { …
  12 methods … }` next to a single concrete struct. Move to consumer or
  split into role-specific interfaces (`Reader`, `Writer`).
- **`return nil, err` without `%w` wrapping.** You lose the call chain.
  Wrap unless the immediate caller is the one logging.
- **Comparing errors with `==`.** Breaks the moment someone wraps. Use
  `errors.Is`. The only exception is `io.EOF` from a function documented
  to return it unwrapped.
- **`go func()` with no exit story.** Every `go` needs an answer for "how
  does this exit when context is cancelled".
- **Channels as data structures.** Use a slice + mutex if it's not a
  signaling primitive.
- **Buffered channel as "rate limit".** Use `errgroup.SetLimit` or a real
  semaphore. Buffered channels mask queue depth instead of bounding it.
- **`sync.WaitGroup` for error-bearing work.** WaitGroup doesn't propagate
  errors. Default to `errgroup`.
- **`time.Sleep` in tests.** Race-prone and slow. Use `<-done` channels,
  deterministic hooks, or an injected clock.
- **`init()` doing real work** (DB connections, file I/O, global state).
  Breaks test isolation and parallelism. Use explicit constructors.
- **Generics for `any`-shaped APIs that work with one type assertion.**
  Generics aren't free — they cost readability.
- **`panic` for control flow.** Panics are for unrecoverable programmer
  errors. Library code should not panic on caller input.

## Output format

For design / API questions:

```
Signature:
    <the type>

Where it lives:
    <consumer vs. producer package, why>

Caller experience:
    <what the call site reads like>

Alternative if <constraint>:
    <the alternative>
```

For concurrency / race / leak debugging:

```
Hypothesis:
    <what you think is happening>

Evidence needed:
    <go test -race output / pprof goroutine / trace>

Likely fix:
    <the fix>

Verification:
    <test that fails before, passes after>
```
