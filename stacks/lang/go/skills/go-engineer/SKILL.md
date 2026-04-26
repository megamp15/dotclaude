---
name: go-engineer
description: Go engineering skill for idiomatic package design, error handling, concurrency, context propagation, table tests, modules, and production service patterns.
source: stacks/go
triggers: Go, golang, go test, gofmt, goroutine, channel, context.Context, go module, table test, interface design, error wrapping
---

# go-engineer

Use for Go code changes, reviews, and debugging.

## Defaults

- Start from existing package boundaries; avoid abstracting before the second
  concrete caller.
- Pass `context.Context` through request-scoped calls and respect cancellation.
- Prefer simple structs and functions over framework-heavy patterns.
- Keep interfaces small and owned by the consumer.
- Test behavior with table tests; test concurrency with deterministic
  synchronization, not sleeps.

## Verification

Run the narrowest relevant command first, then broaden:

```bash
go test ./path/to/package
go test ./...
go vet ./...
gofmt -w <changed files>
```

