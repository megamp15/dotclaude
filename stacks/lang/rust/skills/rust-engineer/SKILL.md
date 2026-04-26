---
name: rust-engineer
description: Production Rust expertise — ownership and lifetimes (when to elide, when to spell, smart pointers), error handling (Result + ? + thiserror/anyhow split), async with tokio (runtime, spawning, Send bounds, select!, cancellation safety), traits and generics, testing with proptest/criterion, and cargo/workspaces. Extends `stacks/lang/rust/CLAUDE.stack.md` with design guidance and failure modes.
source: stacks/lang/rust
triggers: /rust-engineer, Rust, rust 2024 edition, cargo, borrow checker, lifetime, trait, async Rust, tokio, async-std, clippy, rustfmt, unsafe Rust, Result, Option, anyhow, thiserror, serde, axum, tonic, sqlx, criterion, proptest, miri, no_std, embedded Rust
---

# rust-engineer

Production-grade Rust for people who already know the language. Activates
when the question is past style — "why is the borrow checker rejecting
this", "should this be `Box<dyn Trait>` or `impl Trait`", "is this `.await`
holding a lock across a yield point", "how do I structure errors for a
library vs a binary".

> **See also:**
>
> - `stacks/lang/rust/CLAUDE.stack.md` — baseline conventions
> - `stacks/lang/rust/rules/rust-style.md` — enforceable rules
> - `stacks/desktop/tauri/skills/tauri-builder/` — for desktop-app shaped
>   questions
> - `core/skills/architect/` — for "how should I structure this crate"

## When to use this skill

- Designing a public library API with lifetimes and traits.
- Choosing between owned, `&`, `&mut`, `Cow<'_, T>`, `Arc<T>`, `Box<dyn>`.
- Diagnosing a borrow checker error that "should obviously work".
- Debugging an async deadlock or `Send`-bound failure.
- Picking between `thiserror`, `anyhow`, custom enums, and `Box<dyn Error>`.
- Adding `unsafe` with the right hygiene (Safety doc, `// SAFETY:` comments,
  `miri` test).
- Setting up a multi-crate workspace with shared deps and feature unification.

## References (load on demand)

- [`references/ownership-and-lifetimes.md`](references/ownership-and-lifetimes.md)
  — borrow checker reasoning, when to elide vs spell lifetimes, `&mut` vs
  `&`, smart pointers (`Box`, `Rc`, `Arc`, `RefCell`, `Mutex`), interior
  mutability, the `Cow<'_, T>` decision.
- [`references/error-handling.md`](references/error-handling.md) —
  `Result<T, E>` and `?`, the `thiserror` (libraries) vs `anyhow`
  (binaries) split, `From` impls, custom error enums with structured data,
  when to `panic!` vs return an error, `Box<dyn Error>` and its costs.
- [`references/async-and-tokio.md`](references/async-and-tokio.md) —
  tokio runtime model, `tokio::spawn`, `Send` bounds, holding non-`Send`
  state across `.await`, `select!` and cancellation safety,
  `tokio::sync::Mutex` vs `parking_lot::Mutex`, structured concurrency
  with `JoinSet`.
- [`references/testing-and-bench.md`](references/testing-and-bench.md) —
  unit / integration / doc tests, `proptest` and `quickcheck`,
  `criterion` for benchmarks, `cargo-mutants`, `miri` for unsafe code,
  `tokio::test`, snapshot tests with `insta`.
- [`references/cargo-and-workspaces.md`](references/cargo-and-workspaces.md)
  — `Cargo.toml` shape, workspace inheritance (`workspace.dependencies`),
  features (additive!), build scripts, conditional compilation,
  publishing, MSRV policy.

## Core workflow

1. **Classify the question** — ownership / errors / async / traits /
   testing / cargo. Load the relevant reference.
2. **Read the borrow checker error** carefully — it is almost always
   exactly correct. The fix is usually a different ownership shape, not a
   workaround. Reach for `Arc<Mutex<…>>` only after considering owned
   data, splitting borrows, or restructuring control flow.
3. **Make the type system carry real invariants** — newtype wrappers for
   units (`Meters(f64)`), state machines as enums, "validated" types that
   can only be constructed via parsing. The compiler is your friend.
4. **Run the right verification** in this order, narrowing first:
   ```bash
   cargo check                         # fastest sanity
   cargo test --workspace --all-features
   cargo clippy --workspace -- -D warnings
   cargo fmt --all --check
   cargo deny check                    # if configured
   cargo +nightly miri test            # for unsafe code
   ```
5. **Prefer stdlib and the "small std" crates** — `std::collections`,
   `std::io`, `std::sync`, `std::num::NonZero*`, `std::time::Duration`,
   `std::path::Path`. Reach outward only when stdlib genuinely lacks the
   capability (async, allocators, async traits before 1.75).

## Defaults (fast decisions)

| Question | Default |
|---|---|
| Owned vs borrowed return | Return owned for simple data; borrow only when caller's lifetime is clear |
| Function takes `&str` or `String`? | `&str` — caller decides if they have an owned `String` |
| Function returns `&str` or `String`? | `String` unless borrowing from `self` is natural |
| Heap allocation hidden vs visible | Visible — `Box`, `Vec`, `String` over `Cow` magic |
| Shared mutable state in async | `tokio::sync::Mutex` (held across `.await`) or `parking_lot::Mutex` (never held across `.await`) |
| Thread-safe ref-counting | `Arc<T>` (not `Rc`) |
| Library error type | Custom enum with `#[derive(thiserror::Error)]` |
| Binary / app error type | `anyhow::Result<T>` and `anyhow::Context` |
| Async runtime | `tokio` (multi-threaded, default) |
| Spawning a future | `tokio::spawn` for fire-and-forget; `JoinSet` for grouped |
| Bounded concurrency | `JoinSet` + manual count, or `Semaphore` |
| Trait object vs generics | `impl Trait` for ergonomics; `Box<dyn Trait>` for heterogeneity |
| Async traits | Native `async fn` in trait (Rust 1.75+) — `async-trait` only for object-safety |
| Serialization | `serde` with `serde_json` / `bincode` / `postcard` as appropriate |
| HTTP server | `axum` (tokio-native) |
| Database | `sqlx` (compile-time-checked queries) or `diesel` (ORM with macros) |
| Tests with multiple cases | `proptest` for invariants; `rstest` for parametrized |
| Bench | `criterion` |
| Workspace deps | Inherit via `workspace = true` |

## Anti-patterns

- **`unwrap()` in non-test code.** Use `?` with proper error types, or
  `expect("clear message about why this can't fail")` for known
  invariants. Library code should never `unwrap()`.
- **`clone()` to silence the borrow checker.** Often the right fix is a
  different ownership shape, a borrow split, or rethinking the function
  boundary. `clone()` is fine when intentional — annotate with a comment
  if the clone is load-bearing.
- **Holding a `std::sync::Mutex` guard across `.await`.** Either a
  `tokio::sync::Mutex` or scoped lock release. The compiler doesn't
  always catch this; clippy lint `await_holding_lock` does.
- **`async-trait` on every trait.** Native async-fn-in-trait works for
  most cases (Rust 1.75+). Only reach for `async-trait` when you need
  object safety (`Box<dyn MyAsyncTrait>`).
- **`Box<dyn Error>` in libraries.** Caller can't pattern-match. Use a
  `thiserror` enum.
- **`anyhow!` in libraries.** Same problem. `anyhow` is for the
  application layer; `thiserror` is for libraries.
- **Lifetime annotations everywhere "just to be safe".** Elision rules
  cover most cases. Spell lifetimes only when the compiler asks or the
  relationship is non-obvious.
- **`Rc<RefCell<T>>` in code that doesn't need shared ownership.** This
  is "Rust pretending to be a GC language" — usually a sign the design
  needs rethinking.
- **`unsafe` without a `// SAFETY:` comment.** Every `unsafe` block needs
  a comment explaining the invariants the caller is upholding. No
  exceptions.
- **Feature flags that break additivity.** Cargo features must be
  additive — turning one on must not turn another off, must not change
  types of public items, must not break dependents.

## Output format

For ownership / lifetime / borrow questions:

```
Signature:
    <the type, with lifetimes spelled if relevant>

Why this shape:
    <ownership story in 1-2 sentences>

Borrow checker rejects:
    <the alternative>

Because:
    <the rule it violates>
```

For async / runtime debugging:

```
Hypothesis:
    <what you think is happening>

Evidence needed:
    <tokio-console / logs / .await audit>

Likely fix:
    <the fix>

Cancellation safety:
    <yes / no — why>
```
