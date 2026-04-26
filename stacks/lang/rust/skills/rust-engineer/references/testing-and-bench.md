# Testing and benchmarking

Rust's test runner is built into cargo. The conventions:

- **Unit tests** in `#[cfg(test)] mod tests {}` blocks at the bottom of
  each `.rs` file. Test private items here.
- **Integration tests** in `tests/<name>.rs` files at the crate root.
  These see only the public API.
- **Doc tests** in `///` comments — verifies examples compile and run.

```rust
/// Adds two numbers.
///
/// ```
/// assert_eq!(my_crate::add(1, 2), 3);
/// ```
pub fn add(a: i32, b: i32) -> i32 { a + b }

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adds_positive() {
        assert_eq!(add(2, 3), 5);
    }

    #[test]
    fn adds_negative() {
        assert_eq!(add(-1, -2), -3);
    }
}
```

## Running tests

```bash
cargo test                              # all tests
cargo test --lib                        # unit tests only
cargo test --test integration_x         # one integration file
cargo test --doc                        # doc tests only
cargo test some_pattern                 # tests whose name contains pattern
cargo test -- --nocapture               # show stdout (otherwise hidden on pass)
cargo test -- --test-threads=1          # serialize (default is parallel)
```

By default cargo runs tests in parallel within a binary. Mark
non-parallel-safe tests with the `serial_test` crate or design around it.

## Async tests

```rust
#[tokio::test]
async fn fetches_user() {
    let client = Client::new();
    let user = client.get("alice").await.unwrap();
    assert_eq!(user.name, "alice");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn handles_concurrent_load() { … }
```

## Property-based testing

`proptest` generates random inputs and shrinks failures to minimal cases:

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn round_trip(s in "\\PC*") {            // any printable string
        let parsed: String = parse(&serialize(&s));
        prop_assert_eq!(parsed, s);
    }

    #[test]
    fn sorted_is_sorted(mut v in prop::collection::vec(any::<i32>(), 0..100)) {
        v.sort();
        for w in v.windows(2) {
            prop_assert!(w[0] <= w[1]);
        }
    }
}
```

`quickcheck` is older and lighter; `proptest` is more controllable
(strategies, shrinking) and is the modern default.

Use property tests for:

- Round-trip invariants (parse ∘ serialize = id).
- Algebraic properties (commutativity, associativity).
- Differential testing (your impl matches a reference impl).
- Parser/lexer correctness against a grammar.

## Parametrized tests with `rstest`

```rust
use rstest::rstest;

#[rstest]
#[case("0", 0)]
#[case("42", 42)]
#[case("-1", -1)]
fn parses_int(#[case] input: &str, #[case] expected: i32) {
    assert_eq!(parse_int(input), Ok(expected));
}
```

Each case is its own test with its own name. Better than a `for` loop in
a single test (failure messages identify which case failed).

`rstest` also has fixtures (`#[fixture] fn db() -> Db { … }`) — useful but
introduces magic; opinions vary.

## Snapshot tests with `insta`

For tests where the expected output is large and structural (codegen,
formatted output, JSON):

```rust
use insta::assert_yaml_snapshot;

#[test]
fn renders_user() {
    let user = User::new("alice", 30);
    assert_yaml_snapshot!(user);
}
```

First run creates `snapshots/<test_name>.snap`. Subsequent runs diff
against it. Update with `cargo insta review` (interactive) or
`INSTA_UPDATE=always cargo test`.

Use for: rendered HTML, generated code, structured error messages,
parser output. Don't use for: simple equality (regular `assert_eq!` is
clearer).

## Benchmarks with `criterion`

Stable Rust doesn't ship benchmarks; `criterion` is the standard.

`Cargo.toml`:

```toml
[dev-dependencies]
criterion = { version = "0.5", features = ["html_reports"] }

[[bench]]
name = "parse"
harness = false
```

`benches/parse.rs`:

```rust
use criterion::{criterion_group, criterion_main, Criterion, black_box};

fn bench_parse(c: &mut Criterion) {
    c.bench_function("parse_short", |b| {
        b.iter(|| my_crate::parse(black_box("123,456,789")));
    });

    let long = "x,".repeat(10_000);
    c.bench_function("parse_long", |b| {
        b.iter(|| my_crate::parse(black_box(&long)));
    });
}

criterion_group!(benches, bench_parse);
criterion_main!(benches);
```

```bash
cargo bench
```

`black_box` prevents the compiler from optimizing away the work. Reports
land in `target/criterion/<bench>/report/index.html` with statistical
analysis and regression detection vs. the previous run.

## `miri` for unsafe code

Miri is an interpreter that detects undefined behavior:

```bash
rustup component add miri
cargo +nightly miri test
```

Catches:

- Out-of-bounds reads/writes.
- Use-after-free.
- Misaligned pointers.
- Stacked Borrows / Tree Borrows violations.

Slow (~10-100×). Run on the test suite that exercises unsafe code.
Treat any miri finding as a real bug.

## `cargo-mutants`

Mutation testing — modifies your code and checks whether tests catch it:

```bash
cargo install cargo-mutants
cargo mutants
```

Reports "missed" mutations as test gaps. Useful for: confidence in a
critical module, finding tests that are checking nothing meaningful.

## Test organization

- **Unit tests** in the same file as the code. Good for testing private
  helpers and the unit's behavior in isolation.
- **Integration tests** in `tests/`. Each file is a separate binary; tests
  run sequentially within the file but in parallel across files.
- **Common test helpers**: put in a non-test module under `tests/`:
  ```
  tests/
    common/
      mod.rs           ← helpers
    test_a.rs
    test_b.rs
  ```
  Reference with `mod common;` from each test file.

## Mocking philosophy

Rust's culture: hand-rolled fakes over magic mocks. Define a trait, write
a fake implementation:

```rust
trait Clock { fn now(&self) -> Instant; }

struct SystemClock;
impl Clock for SystemClock { fn now(&self) -> Instant { Instant::now() } }

struct TestClock(Instant);
impl Clock for TestClock { fn now(&self) -> Instant { self.0 } }
```

`mockall` exists for "I don't want to hand-write fakes" but it's
controversial — the macro-generated mocks couple tests tightly to
implementation. Consider whether the design wants the dependency
inverted instead.

## Anti-patterns

- **Testing private helpers in isolation when the public API would
  exercise them.** You're locking in implementation.
- **`unwrap()` chains in tests** when `?` would work — `#[test] fn
  foo() -> Result<()>` is supported.
- **Missing `--release` for benchmarks.** Debug-mode timings are
  meaningless. Criterion handles this; `cargo bench` does too. But if
  you're doing `cargo run --example bench`, add `--release`.
- **`thread::sleep` for "wait for X to happen".** Flaky. Use channels,
  notify primitives, or fake clocks.
- **Tests that depend on test execution order.** They will eventually
  run in a different order (parallelization, filtering).
- **Snapshot tests for everything.** Most tests are clearer with
  explicit `assert_eq!`. Snapshots earn their keep for genuinely
  structural output.
