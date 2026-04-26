# Modules and tooling

`go.mod` since 1.11, workspaces since 1.18, generics since 1.18, range-
over-int since 1.22, `for-range` per-iteration variable since 1.22, `slog`
in stdlib since 1.21. The 2026 baseline is Go 1.22+; targeting older is a
deliberate choice.

## `go.mod` shape

```
module github.com/acme/payments

go 1.22

require (
    github.com/jackc/pgx/v5 v5.5.0
    golang.org/x/sync v0.6.0
)

require (
    // indirect deps appear here automatically
)
```

Keep direct and indirect requires separate (the toolchain does this for
you on `go mod tidy`). `go.sum` must be committed; it's the lockfile.

After any dependency change:

```bash
go mod tidy
```

This adds missing requires, removes unused ones, and stabilizes the file.
Run it before commit.

## Workspaces (`go.work`)

For multi-module repos where modules import each other in development
*without* `replace` directives in `go.mod`:

```
go work init ./service-a ./service-b ./shared
```

This creates `go.work` (committed) and `go.work.sum` (committed). Each
module keeps its own `go.mod`; the workspace tells the toolchain "while
working in this repo, these are the source-of-truth versions of these
modules".

Workspaces don't ship to consumers — when someone `go get`s your module,
they see only your `go.mod`. That's the point. Keep release coupling
explicit.

## `replace` directives — and why workspaces are usually better

```
replace github.com/acme/shared => ../shared
```

This rewires a require to a local path or different version. Used to be
the standard pattern for local development; workspaces superseded it
because:

- `replace` lives in `go.mod`, which ships. Easy to forget and accidentally
  publish.
- `replace` doesn't compose — multiple developers had to manually edit
  `go.mod`.
- Workspaces are local-only by design.

Use `replace` only when:

- Forking an upstream temporarily (`replace github.com/foo/bar =>
  github.com/yourname/bar v0.0.0-…`).
- Pinning to a specific commit while a fix is upstream (`replace … =>
  github.com/foo/bar v0.0.0-yyyymmddhhmmss-shorthash`).

Always remove `replace` directives before tagging a release.

## Build tags

Conditional compilation. Two equivalent forms — the new is preferred:

```go
//go:build linux && amd64

package foo
```

Common tags:

- `//go:build !windows` — exclude Windows
- `//go:build integration` — only when running `go test -tags=integration`
- `//go:build go1.22` — version-gated

Don't overuse build tags. Too many configurations means too many things
to test.

## `go vet`

Always run. Catches mistakes the compiler doesn't:

```bash
go vet ./...
```

Detects: shadowed variables, struct tag typos, `printf` format mismatches,
unreachable code, copy-locks (`sync.Mutex` copied by value), and more.
Failure should fail CI.

## `staticcheck`

The de facto Go linter. More aggressive than `vet`. Catches things like
`if err != nil; return err` chains that lose context, channel leaks, slice
bounds checks, deprecated API usage.

```bash
go install honnef.co/go/tools/cmd/staticcheck@latest
staticcheck ./...
```

CI failure on `staticcheck` finding is a reasonable default. Disable
specific checks via `// lint:ignore SA…`-style comments when warranted.

## `gofumpt`

Stricter than `gofmt`. Removes more debate over formatting (no `if
err != nil { return err }` on a single line, etc.). Many teams adopt it
because the alternative is bikeshedding.

```bash
go install mvdan.cc/gofumpt@latest
gofumpt -l -w .
```

If your team uses `gofmt`, that's fine — just be consistent.

## `golangci-lint`

Meta-linter that runs many at once. Configured via `.golangci.yml`:

```yaml
linters:
  enable:
    - errcheck
    - govet
    - staticcheck
    - revive
    - gocritic
    - gosec
    - errorlint
    - bodyclose
    - noctx           # http requests must use NewRequestWithContext
    - rowserrcheck
    - sqlclosecheck

linters-settings:
  errcheck:
    check-type-assertions: true
```

A reasonable starter set. Iterate based on what your team finds noisy vs.
useful.

## Module layout patterns

### Single binary, simple

```
my-service/
├── go.mod
├── main.go
├── handler.go
├── handler_test.go
└── store/
    ├── store.go
    └── store_test.go
```

Fine. Tests beside code.

### Multi-binary repo

```
my-org/
├── go.mod
├── cmd/
│   ├── api/main.go
│   ├── worker/main.go
│   └── migrate/main.go
├── internal/
│   ├── api/         # not importable outside this module
│   ├── store/
│   └── auth/
└── pkg/             # exported library code (use sparingly)
    └── eventbus/
```

`internal/` is enforced by the toolchain — anything under `internal/`
can only be imported by packages rooted at `internal/`'s parent or
deeper. Use it freely.

`pkg/` is convention, not enforced. Only put code there if external
projects will import it. Otherwise it's just `internal/` with worse
discoverability.

### Multi-module monorepo

```
my-org/
├── go.work
├── service-a/
│   └── go.mod
├── service-b/
│   └── go.mod
└── shared/
    └── go.mod
```

When the modules ship independently. Each gets its own `go.mod` and can
release on its own version. The workspace ties them together for dev.

## Versioning

SemVer. `v0.x` means breaking changes between minors. `v1.x` is a
contract; breaking changes require `v2`.

`v2+` modules must use a major-version path suffix:

```
module github.com/acme/payments/v2
```

Importers `import "github.com/acme/payments/v2"`. This is the toolchain's
mechanism for keeping multiple major versions buildable in one `go.sum`.

Tag as `v1.2.3` (with the `v` prefix). `go list -m -versions
github.com/acme/payments` lists known versions.

## Vendoring

```bash
go mod vendor
```

Creates a `vendor/` directory with all dependencies. Builds use it
automatically. Useful when:

- Network-restricted CI / build environments.
- You need air-gapped builds.
- You distribute source-only releases.

Most teams skip it now — module proxy + `go.sum` integrity checks are
sufficient.

## Useful tools

- `go doc <pkg>` / `go doc <pkg>.Symbol` — local godoc.
- `go test -coverprofile=cover.out && go tool cover -html=cover.out` —
  HTML coverage view.
- `go test -bench=. -benchmem` — benchmarks.
- `go tool pprof http://localhost:6060/debug/pprof/profile?seconds=30`
  — CPU profile.
- `dlv debug ./cmd/api` — Delve debugger.
- `goimports -w .` — `gofmt` plus import management.
