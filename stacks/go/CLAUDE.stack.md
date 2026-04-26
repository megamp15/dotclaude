---
source: stacks/go
---

# Go stack

- Prefer small packages with explicit interfaces at boundaries.
- Keep context propagation explicit; accept `context.Context` as the first
  parameter for request-scoped work.
- Return errors with useful wrapping and avoid panic outside startup/test code.
- Use table tests for behavior matrices and focused integration tests for I/O.
- Run `go test ./...`, `go vet ./...`, and formatting before completion.

