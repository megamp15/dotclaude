# Error handling

Rust's error story has converged on `Result<T, E>` + `?` for propagation,
plus a clean split between **library** errors (typed enums via
`thiserror`) and **application** errors (dynamic via `anyhow`).

## `Result<T, E>` and `?`

```rust
fn read_config(path: &Path) -> Result<Config, Error> {
    let s = std::fs::read_to_string(path)?;          // io::Error converts via From
    let cfg: Config = toml::from_str(&s)?;           // toml::de::Error converts
    Ok(cfg)
}
```

`?` does:

1. If `Result::Ok(v)`, evaluates to `v`.
2. If `Result::Err(e)`, returns early after `e.into()` (i.e. `From` conversion
   to the function's error type).

`From<InnerError>` impls are how multiple error types unify under one
top-level error.

## The library / application split

**Libraries** publish typed errors. Callers can pattern-match, you can
provide structured data, and the API contract is checkable.

```rust
use thiserror::Error;

#[derive(Debug, Error)]
pub enum DbError {
    #[error("connection failed: {0}")]
    Connection(#[from] sqlx::Error),

    #[error("constraint violated: {field}")]
    Constraint { field: String },

    #[error("row not found: id={id}")]
    NotFound { id: String },

    #[error("invalid query: {reason}")]
    InvalidQuery { reason: String },
}
```

**Applications** use `anyhow` for ergonomics. Caller is "the program",
which doesn't pattern-match — it just logs and exits.

```rust
use anyhow::{Context, Result};

fn main() -> Result<()> {
    let cfg = read_config(Path::new("/etc/app.toml"))
        .context("loading startup configuration")?;
    let db = connect(&cfg.db_url)
        .with_context(|| format!("connecting to {}", cfg.db_url))?;
    serve(db).context("starting HTTP server")?;
    Ok(())
}
```

`Context::context` adds a description; `with_context` is lazy (closure
runs only on error). The chain shows in `Debug` print:

```
Error: starting HTTP server
Caused by:
    0: connecting to postgres://…
    1: io error: Connection refused (os error 111)
```

## When to use which

| Use | When |
|---|---|
| `thiserror` enum | Library; callers may pattern-match; structured failure modes |
| `anyhow::Result` | Binary / application; you'll just propagate and log |
| Custom enum without thiserror | When the macro overhead isn't worth it (≤ 3 variants, no source chains) |
| `Box<dyn Error>` | Almost never. Cannot pattern-match; loses structure. |
| `&'static str` / `String` | Examples and prototypes only |
| `()` as error | Never. Tells the caller nothing. |

## `From` impls and the `?` chain

The clean way to unify a function that calls multiple error-returning
APIs:

```rust
#[derive(Debug, Error)]
pub enum AppError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),

    #[error("parse: {0}")]
    Parse(#[from] toml::de::Error),

    #[error("validation: {0}")]
    Validation(String),
}

fn load(path: &Path) -> Result<Config, AppError> {
    let s = std::fs::read_to_string(path)?;        // io::Error → AppError::Io
    let cfg: Config = toml::from_str(&s)?;         // toml::de::Error → AppError::Parse
    cfg.validate()
        .map_err(|e| AppError::Validation(e.to_string()))?;
    Ok(cfg)
}
```

`#[from]` on a variant generates `From<innerError>` for the enum.

## When to add context vs not

- **At domain boundaries** (function entry, layer transitions) — yes,
  add a `.context("what this function was trying to do")`.
- **Inside a single function** with already-clear error messages — no.
  `?` is enough.
- **Programmer errors** (impossible cases) — `expect("clear reason")`,
  not `unwrap()`. The message is for the next person reading the panic.

## Custom error types — the manual way

Without `thiserror`:

```rust
use std::fmt;

#[derive(Debug)]
pub enum ConfigError {
    Missing { field: &'static str },
    Invalid { field: &'static str, reason: String },
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Missing { field } => write!(f, "missing field: {field}"),
            Self::Invalid { field, reason } => write!(f, "invalid {field}: {reason}"),
        }
    }
}

impl std::error::Error for ConfigError {}
```

Use this when the macro feels heavy. For 5+ variants with source chains,
`thiserror` saves real boilerplate.

## Source chains

`std::error::Error` has a `source()` method that returns the wrapped
cause. Walking the chain:

```rust
fn print_chain(err: &dyn std::error::Error) {
    let mut current: Option<&dyn std::error::Error> = Some(err);
    while let Some(e) = current {
        eprintln!("- {e}");
        current = e.source();
    }
}
```

`thiserror`'s `#[source]` and `#[from]` attributes handle this for you.
`anyhow`'s `Debug` print walks the chain automatically.

## When to `panic!`

- **Unrecoverable programmer error**: invariants the type system can't
  express but should always hold.
- **Tests**: `panic!` and `unwrap()` are fine; failure means test fails.
- **`unreachable!()`** for "this branch is impossible by construction";
  acts as a panic if reached.
- **`todo!()`** for "I haven't written this yet"; explicit placeholder.

Production library code should not panic on user input. That's a bug.

## `?` works for `Option` too

```rust
fn first_word(s: &str) -> Option<&str> {
    let space = s.find(' ')?;
    Some(&s[..space])
}
```

Combine `Result` and `Option`:

```rust
let value = map.get(&key).ok_or(NotFound)?;
```

Or:

```rust
let value = map.get(&key).context("key missing")?;
```

(`anyhow`'s `Context` is implemented for `Option` too.)

## Anti-patterns

- **`.unwrap()` outside tests / examples / known-true invariants.**
  Almost always a hidden runtime panic.
- **`Box<dyn Error>` in libraries.** Caller can't introspect.
- **`anyhow!()` in libraries.** Same problem.
- **Catching all errors at one big `match`** that just maps everything
  to a generic message. You're erasing information. Match on specific
  variants you care about; let the rest propagate.
- **`Result<T, String>`** — no source chain, can't pattern-match,
  allocates on every error.
- **Nested `Result<Result<T, E1>, E2>`** — flatten with `?` and `From`
  impls, or `.and_then`, or change the design.
- **`if err.to_string().contains("not found")`** — string-matching error
  messages. Use typed errors and pattern-match on the variant.
- **Logging an error and re-throwing it.** Logs once at the top boundary;
  bubble everywhere else.
