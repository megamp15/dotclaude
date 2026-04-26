---
source: stacks/rust
---

# Rust stack

- Model invalid states with types where it pays for itself.
- Keep ownership and lifetime complexity local; do not leak hard lifetimes into
  public APIs unless the performance need is real.
- Prefer `Result<T, E>` and meaningful error types over stringly errors.
- Use `cargo check`, `cargo test`, `cargo fmt`, and `cargo clippy` before
  claiming completion.

