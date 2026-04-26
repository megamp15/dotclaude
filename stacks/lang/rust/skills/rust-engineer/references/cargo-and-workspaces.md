# Cargo and workspaces

Rust 2024 edition + cargo's workspace inheritance is the modern shape
for any project bigger than a single crate.

## `Cargo.toml` shape

```toml
[package]
name = "my-service"
version = "0.1.0"
edition = "2024"
rust-version = "1.78"               # MSRV — minimum supported Rust version
description = "Does the thing"
license = "MIT OR Apache-2.0"

[dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
anyhow = "1"

[dev-dependencies]
proptest = "1"
criterion = { version = "0.5", features = ["html_reports"] }

[[bench]]
name = "parse"
harness = false                     # required for criterion
```

Pin to a major version (`"1"`), not exact (`"1.2.3"`) — cargo resolves to
the latest compatible. `Cargo.lock` is the lockfile (committed for
binaries, not for libraries).

`rust-version` (MSRV) signals the minimum Rust version your crate
supports. Bump it deliberately — it's a breaking change for downstream.

## Workspaces

For multi-crate repos:

```
my-service/
├── Cargo.toml          ← workspace root
├── Cargo.lock          ← shared lockfile
├── crates/
│   ├── api/
│   │   ├── Cargo.toml
│   │   └── src/lib.rs
│   ├── domain/
│   │   ├── Cargo.toml
│   │   └── src/lib.rs
│   └── store/
│       ├── Cargo.toml
│       └── src/lib.rs
└── bin/
    └── server/
        ├── Cargo.toml
        └── src/main.rs
```

Workspace `Cargo.toml`:

```toml
[workspace]
resolver = "3"                      # Rust 2024 default
members = ["crates/*", "bin/*"]

[workspace.package]
version = "0.1.0"
edition = "2024"
rust-version = "1.78"
license = "MIT OR Apache-2.0"

[workspace.dependencies]
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
thiserror = "1"
anyhow = "1"
```

Member crates inherit:

```toml
# crates/api/Cargo.toml
[package]
name = "my-api"
version.workspace = true
edition.workspace = true
rust-version.workspace = true

[dependencies]
tokio.workspace = true
serde.workspace = true
my-domain = { path = "../domain" }
```

Benefits:

- One `Cargo.lock` for the whole workspace — consistent versions across
  crates.
- One `target/` — shared build artifacts.
- Single source of truth for common dep versions (`workspace.dependencies`).
- `cargo build`/`cargo test` from any directory builds everything.

## Path dependencies

```toml
my-domain = { path = "../domain" }
```

Cargo follows local paths. For development, this is enough. For
publishing, you must specify a version too:

```toml
my-domain = { path = "../domain", version = "0.1.0" }
```

When publishing, cargo strips path entries and uses the version. Local
dev still resolves to the local copy.

## Features

Features are **additive flags** — turning one on adds capabilities, never
breaks existing ones.

```toml
[features]
default = ["http"]
http = ["dep:reqwest"]
grpc = ["dep:tonic", "dep:prost"]
postgres = ["dep:sqlx", "sqlx/postgres"]

[dependencies]
reqwest = { version = "0.12", optional = true }
tonic = { version = "0.11", optional = true }
prost = { version = "0.12", optional = true }
sqlx = { version = "0.7", optional = true }
```

`#[cfg(feature = "http")]` to gate code:

```rust
#[cfg(feature = "http")]
pub mod http_client;
```

Run with feature combos:

```bash
cargo build                              # default features
cargo build --no-default-features
cargo build --no-default-features --features http
cargo build --all-features
```

CI must test multiple feature combinations — at minimum
`--no-default-features` and `--all-features`. The `cargo-hack` tool
automates this (`cargo hack --feature-powerset test`).

The cardinal rule: **features must be additive**. A feature flag that
removes a public item, changes a type's signature, or breaks a
dependent's expectations is a mistake. Features compose at build time,
and dependents may activate features you didn't expect.

## Build scripts (`build.rs`)

For codegen, environment detection, linking native libs:

```rust
// build.rs
fn main() {
    println!("cargo:rerun-if-changed=schema.proto");
    prost_build::compile_protos(&["schema.proto"], &["."]).unwrap();
}
```

`Cargo.toml`:

```toml
[build-dependencies]
prost-build = "0.12"
```

Use sparingly. Build scripts run on every compile, slow CI, and add
opacity. Consider `include_str!`/`include_bytes!` first.

## Conditional compilation

```rust
#[cfg(target_os = "linux")]
fn platform_specific() { … }

#[cfg(any(unix, target_os = "redox"))]
fn unix_or_redox() { … }

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn linux_x86() { … }

#[cfg(not(test))]
const DEFAULT_PORT: u16 = 8080;

#[cfg(test)]
const DEFAULT_PORT: u16 = 0;
```

`#[cfg_attr(condition, attribute)]` for conditionally adding attributes:

```rust
#[cfg_attr(feature = "serde", derive(serde::Serialize))]
struct Config { … }
```

## Cross-compilation

```bash
rustup target add aarch64-unknown-linux-gnu
cargo build --target aarch64-unknown-linux-gnu
```

For C deps, you'll often need `cross` (Docker-based cross-compile):

```bash
cargo install cross
cross build --target aarch64-unknown-linux-gnu --release
```

For musl-static builds:

```bash
rustup target add x86_64-unknown-linux-musl
cargo build --target x86_64-unknown-linux-musl --release
```

## Publishing

```bash
cargo publish --dry-run
cargo publish
```

Requires `crates.io` token (`cargo login`). Once published, **a version
cannot be removed** — only `cargo yank` (which prevents new deps from
resolving to it but doesn't break existing `Cargo.lock`).

Pre-publish checklist:

- [ ] `Cargo.toml` has `description`, `license`, `repository`,
      `documentation`.
- [ ] `README.md` exists.
- [ ] Version bumped per SemVer.
- [ ] `CHANGELOG.md` updated.
- [ ] `cargo doc --no-deps` succeeds without warnings.
- [ ] `cargo test` passes on MSRV.

## `cargo deny` and supply chain

```bash
cargo install cargo-deny
cargo deny check
```

Verifies:

- No banned crates (configurable).
- License allowlist.
- No known vulnerabilities (RustSec advisory DB).
- No duplicate versions of major deps.

Add to CI. The config (`deny.toml`) takes some tuning to fit your
project's policy.

## Useful cargo subcommands

| Command | Purpose |
|---|---|
| `cargo check` | Compile-check without codegen — fastest sanity loop |
| `cargo clippy` | Lints. `-- -D warnings` makes them errors |
| `cargo fmt` | Format. `--check` for CI |
| `cargo doc --open` | Build and open docs |
| `cargo expand` | Expand macros (install `cargo-expand`) |
| `cargo tree` | Dependency tree. `-d` for duplicates, `-i <crate>` for inverse |
| `cargo update` | Update `Cargo.lock` |
| `cargo audit` | Vulnerability scan against RustSec DB |
| `cargo outdated` | Show deps with newer versions available |
| `cargo bloat` | Binary size analysis (install `cargo-bloat`) |
| `cargo udeps` | Find unused deps (nightly) |
| `cargo machete` | Find unused deps (stable alternative) |

## Anti-patterns

- **`* = "*"`** — wildcard versions. Cargo will refuse to publish.
- **Path deps without version** in published crates. Build fails on
  consumers.
- **Features that aren't additive** — removing items, changing types.
- **`build.rs` doing things that could be `include_str!`.** Cost without
  benefit.
- **`workspace.dependencies` listing every dep**, including ones used by
  one crate. Add only what's shared.
- **MSRV drift** — bumping rust-version casually breaks downstream. Bump
  intentionally with a changelog entry.
- **Committing `Cargo.lock` for libraries** — convention is no, because
  applications using your lib should own their lockfile. Commit for
  binaries, exclude for libraries.
