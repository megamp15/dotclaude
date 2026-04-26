---
source: stacks/rust
---

# Rust style

- Avoid `unwrap` / `expect` in library and request-handling code unless the
  invariant is obvious and documented.
- Prefer iterators when they make ownership clearer; use loops when they are
  easier to read.
- Keep async boundaries explicit; do not hold mutex guards across `.await`.
- Use newtypes for IDs and units that can be confused.
- Add regression tests for unsafe code and document every unsafe block.

