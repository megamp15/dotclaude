# Testing

Go's testing toolkit is small but enough. Tests live in `_test.go` files
beside the code they test. Run with `go test`, instrument with `-race` and
`-cover`. Don't fight the conventions.

## Table tests

The default shape for any function with multiple inputs:

```go
func TestParse(t *testing.T) {
    tests := []struct {
        name    string
        input   string
        want    Token
        wantErr bool
    }{
        {"empty",    "",       Token{},        true},
        {"number",   "42",     Token{Int: 42}, false},
        {"trailing", "42 abc", Token{},        true},
    }
    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            got, err := Parse(tt.input)
            if (err != nil) != tt.wantErr {
                t.Fatalf("err = %v, wantErr = %v", err, tt.wantErr)
            }
            if got != tt.want {
                t.Errorf("got %+v, want %+v", got, tt.want)
            }
        })
    }
}
```

Each `t.Run(tt.name, …)` produces a separate subtest visible in `-v`
output and runnable individually with `go test -run TestParse/empty`.

In Go ≥ 1.22, the loop variable is captured per iteration, so no `tt :=
tt` shadow needed. In older code, keep the shadow.

## `t.Helper()` and `t.Cleanup()`

`t.Helper()` makes failure locations point at the *caller*, not the
helper:

```go
func mustParse(t *testing.T, s string) Token {
    t.Helper()
    tok, err := Parse(s)
    if err != nil { t.Fatalf("parse %q: %v", s, err) }
    return tok
}
```

`t.Cleanup(fn)` runs at the end of the test (or subtest), even on
failure. Use it instead of `defer` so cleanup composes across helpers:

```go
func setup(t *testing.T) *DB {
    t.Helper()
    db := openTestDB(t)
    t.Cleanup(func() { db.Close() })
    return db
}
```

## Assertions

Stdlib first. `if got != want { t.Errorf("got %v, want %v", got, want) }`.

When the comparison is structural and complex (deep struct equality), use
`reflect.DeepEqual` or `cmp.Diff`:

```go
import "github.com/google/go-cmp/cmp"

if diff := cmp.Diff(want, got); diff != "" {
    t.Errorf("Foo() mismatch (-want +got):\n%s", diff)
}
```

`go-cmp` is the one external testing dep most production code wants.
`testify`'s `assert` and `require` are popular but encourage failure-by-
panic patterns; if you use `testify`, prefer `require` (which calls
`t.Fatal`) over `assert` (which calls `t.Error`) when the test can't
meaningfully continue.

## HTTP testing with `httptest`

Don't mock the HTTP client. Run a real test server:

```go
func TestClient_Fetch(t *testing.T) {
    srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        if r.URL.Path != "/users/42" {
            http.Error(w, "not found", http.StatusNotFound)
            return
        }
        json.NewEncoder(w).Encode(User{ID: "42", Name: "alice"})
    }))
    defer srv.Close()

    c := NewClient(srv.URL)
    user, err := c.Fetch(context.Background(), "42")
    if err != nil { t.Fatal(err) }
    if user.Name != "alice" { t.Errorf("got %q", user.Name) }
}
```

For TLS testing, `httptest.NewTLSServer`. For unstable connections,
`net.Listen("tcp", "127.0.0.1:0")` and write your own handler.

## Fuzz tests

For input parsers and serializers:

```go
func FuzzParse(f *testing.F) {
    f.Add("42")
    f.Add("0")
    f.Fuzz(func(t *testing.T, input string) {
        tok, err := Parse(input)
        if err != nil { return }      // any error is fine
        // invariant: serializing back round-trips
        if got := tok.String(); got != input && tok.canonicalize(input) != got {
            t.Errorf("round-trip: %q -> %v -> %q", input, tok, got)
        }
    })
}
```

Run with `go test -fuzz=FuzzParse -fuzztime=30s`. Save discovered crashes
to `testdata/fuzz/FuzzParse/` automatically.

## Golden files

For tests that produce structured output (HTML, JSON, codegen):

```go
got := generate(input)
golden := filepath.Join("testdata", t.Name() + ".golden")
if *update {
    os.WriteFile(golden, got, 0644)
}
want, _ := os.ReadFile(golden)
if !bytes.Equal(got, want) {
    t.Errorf("golden mismatch; run with -update")
}
```

Add a `-update` flag at the top:

```go
var update = flag.Bool("update", false, "update golden files")
```

## The race detector

```bash
go test ./... -race -count=1
```

`-count=1` defeats the test cache; without it, unchanged tests don't
re-run. CI must pass with `-race`. Local dev usually too — the slowdown
is bearable.

## Test parallelism

`t.Parallel()` makes the test (or subtest) run alongside others marked
with the same call. Default to *not* parallel — it interacts with shared
state (env vars, file system, port allocation) in ways that make tests
flaky if you're not careful.

When you do parallelize, be explicit about the shared state. `t.Setenv`
is non-parallel-safe (it stops parallelism for that test); plan around
that.

## What to test, what not to

- **Test the public API.** Internal helpers tested via the public API are
  fine. Helpers tested in isolation lock in implementation.
- **Test edge cases.** Empty input, max input, off-by-one, boundary
  conditions, error paths.
- **Test the error paths.** Most production bugs are wrong error handling,
  not wrong happy paths.
- **Don't test the framework.** No tests for `gorm.Save` itself, only
  your code that calls it.

## Anti-patterns

- **`time.Sleep` in tests.** Race-prone. Use channels, an injected clock,
  or a poll-with-timeout helper.
- **Global state setup in `TestMain` without teardown.** Tests must be
  hermetic enough that `go test -run TestX` works in any order.
- **Assertions that mask failures** (`if got >= 0`). Be specific.
- **Test names that describe the test ("test_foo_returns_correct_value")**.
  Test names describe the scenario (`TestFoo_EmptyInput_ReturnsError`).
- **Duplicating production logic in the test to compute the expected
  value.** If your test computes the same way the code does, both are
  wrong together. Hardcode the expected output.
- **Catching `panic`s in tests with `recover` to "make tests robust"**.
  A panic *is* a test failure; let it fail loudly.
