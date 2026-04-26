---
name: rust-engineer
description: Rust engineering skill for ownership, lifetimes, error types, async, traits, cargo workflows, testing, and performance-sensitive code.
source: stacks/rust
triggers: Rust, cargo, borrow checker, lifetime, trait, async Rust, tokio, clippy, rustfmt, unsafe Rust, Result, serde
---

# rust-engineer

Use for Rust implementation, review, and debugging.

## Defaults

- Make the type system carry real invariants, not ceremonial wrappers.
- Keep public APIs simple; hide complex lifetimes behind owned values or
  builders unless borrowing is central to the design.
- Prefer explicit error enums for libraries and contextual errors for apps.
- Treat `unsafe` as a tiny, documented boundary with tests around it.

## Verification

```bash
cargo check
cargo test
cargo fmt --check
cargo clippy -- -D warnings
```

