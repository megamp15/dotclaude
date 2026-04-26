---
source: stacks/go
---

# Go style

- Keep exported identifiers documented when they are part of a public package.
- Avoid package-level mutable state unless it is guarded and intentionally
  process-wide.
- Prefer dependency injection through constructors over global clients.
- Make goroutine lifetimes obvious; every background goroutine needs a shutdown
  path or parent context.
- Use `errors.Is` / `errors.As` for sentinel and typed errors.

