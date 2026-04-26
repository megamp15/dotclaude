# Concurrency

Go's concurrency primitives are simple but composable in ways that hide
subtle bugs. The rules below are the ones that prevent the bugs you actually
hit in production.

## The cardinal rule

Every `go` statement needs an answer to: **"How does this goroutine exit
when the surrounding context is cancelled?"**

If the answer is "it doesn't", you've written a leak. If the answer is "the
channel will close eventually", verify *who* closes it and *when*.

## `context.Context` propagation

`context.Context` is the first parameter of any function that does I/O or
might block. It is not optional. It is not for "passing extra data" — that's
a structured-context anti-pattern; pass values explicitly.

```go
func Fetch(ctx context.Context, id string) (*User, error) {
    req, err := http.NewRequestWithContext(ctx, "GET", url(id), nil)
    if err != nil { return nil, fmt.Errorf("build req: %w", err) }
    // ...
}
```

Every blocking call respects cancellation:

```go
select {
case <-ctx.Done():
    return ctx.Err()
case result := <-ch:
    // ...
}
```

A `context.Context` is not stored on a struct — it lives on the call stack.
The exception is request-scoped middleware where the lifetime is clear.

## Goroutine lifecycle: starting, joining, leaking

The four shapes of a goroutine you can actually reason about:

1. **Fire-and-forget with explicit lifetime** — `go func() { … }()` inside a
   function that has a `defer cancel()` and a `<-ctx.Done()` exit.
2. **Joined via WaitGroup** — only when no error needs to propagate. Rare in
   practice; almost always replaceable with `errgroup`.
3. **Joined via errgroup** — the default for "do these N things in parallel,
   any failure cancels the rest".
4. **Long-lived service goroutine** — started in main, exited via a `done`
   channel signaled at shutdown. Document the contract.

Anything else (especially "I'll just `go func()` here and trust the GC") is
a leak waiting to be diagnosed via `pprof goroutine`.

## `errgroup` is the default

```go
import "golang.org/x/sync/errgroup"

g, ctx := errgroup.WithContext(ctx)
for _, item := range items {
    item := item                 // shadow before Go 1.22; explicit for clarity
    g.Go(func() error {
        return process(ctx, item)
    })
}
if err := g.Wait(); err != nil {
    return fmt.Errorf("process batch: %w", err)
}
```

Bound concurrency:

```go
g.SetLimit(8)                    // at most 8 goroutines from this group
```

`errgroup.WithContext(ctx)` returns a context that is cancelled the moment
*any* `g.Go` returns a non-nil error. Other in-flight goroutines see
`ctx.Done()` and should bail. Wait returns the *first* non-nil error.

## Channel patterns

**Done channel** — signal-only, type `chan struct{}`:
```go
done := make(chan struct{})
go func() {
    defer close(done)
    work()
}()
<-done
```

**Fan-out / fan-in** — N workers from one input channel, results to one
output. Close the input when the producer is done; the workers' range loops
exit; close the output once all workers exit.

**Bounded semaphore** — buffered channel as a counting semaphore:
```go
sem := make(chan struct{}, 8)
for _, item := range items {
    sem <- struct{}{}
    go func(item Item) {
        defer func() { <-sem }()
        process(item)
    }(item)
}
```

Prefer `errgroup.SetLimit` unless you specifically need the channel-shape.

**Pipeline** — chain of stages, each a goroutine reading from the previous
stage's output channel and writing to the next. Always have a way to
propagate cancellation up the chain (typically by selecting on `ctx.Done()`
in the read).

## `sync` primitives — when channels aren't right

- `sync.Mutex` / `sync.RWMutex` — protecting shared state. Default to
  `Mutex`; reach for `RWMutex` only when you measure read contention.
- `sync.Once` — one-shot initialization. Common with lazy singletons.
- `sync.Pool` — pool of reusable allocations for performance-sensitive
  paths. Easy to misuse — don't reach for it without a profile showing
  allocation pressure.
- `sync.Map` — only when keys are write-once-read-many or stable. For most
  cases, `map[K]V` + `sync.Mutex` is faster and clearer.
- `sync/atomic` — atomic primitives. Prefer `atomic.Int64`, `atomic.Pointer[T]`
  (Go 1.19+) over the loose `atomic.AddInt64(&x, 1)` style.

## `singleflight` for in-flight deduplication

When N callers ask for the same expensive thing concurrently, do it once:

```go
import "golang.org/x/sync/singleflight"

var g singleflight.Group

func GetUser(ctx context.Context, id string) (*User, error) {
    v, err, _ := g.Do(id, func() (any, error) {
        return fetchUser(ctx, id)   // expensive
    })
    if err != nil { return nil, err }
    return v.(*User), nil
}
```

The third return value (`shared bool`) tells you whether other callers
piggybacked. Useful for metrics; ignorable otherwise.

## The race detector

```bash
go test -race ./...
go run -race ./cmd/server
```

CI must run with `-race`. The race detector catches read/write races by
instrumenting memory access — it doesn't catch logical races (TOCTOU,
ordering bugs in error paths). It runs ~2× slower; build times are similar.

If a test is "flaky only with -race", you have a real race, not a flaky
test. Don't suppress, fix.

## Common leak shapes

1. **Goroutine waiting on a channel that's never sent to / closed.** Found
   via `pprof goroutine` showing many goroutines parked at the same `chan
   send`/`chan receive`.
2. **Producer never closes the channel** because of an early-return path
   that skipped the close. Use `defer close(out)` at the top of the
   producer.
3. **Context leaked across boundaries** — passing a `context.Background()`
   to a goroutine that survives the request. Pass the *request* context.
4. **Ticker / timer not stopped.** `time.NewTicker` in a goroutine that
   exits without `ticker.Stop()` leaks the timer.
5. **HTTP response body not closed** — not exactly a goroutine leak but
   leaks the underlying connection. Always `defer resp.Body.Close()` and
   read or `io.Copy(io.Discard, …)` to enable connection reuse.

## Diagnosing concurrency bugs

```bash
# is something stuck?
curl http://localhost:6060/debug/pprof/goroutine?debug=1

# from within a test, dump on hang:
go test -timeout 30s -run TestX
# the timeout panic prints all goroutine stacks
```

Build with `-tags=netgo` and add `net/http/pprof` to expose runtime profiles
on a debug port.
