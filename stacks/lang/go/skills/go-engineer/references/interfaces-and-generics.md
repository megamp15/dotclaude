# Interfaces and generics

The two abstraction tools in Go. The defaults: prefer concrete returns,
small consumer-side interfaces, and reach for generics only when the
type-asserted alternative is unsafe or noisy.

## "Accept interfaces, return concrete types"

The most-quoted Go advice, and still the right default.

```go
// good — accepts whatever satisfies the contract
func Save(w io.Writer, data []byte) error {
    _, err := w.Write(data)
    return err
}

// good — concrete return; caller can use it however they want
func NewClient(cfg Config) *Client { … }
```

Returning an interface from a constructor forces the caller through that
interface even when they need methods that aren't on it. Concrete returns
let callers compose freely.

The exception: when the constructor genuinely returns one of several
implementations chosen at runtime — e.g. `func Open(scheme string) (Storage,
error)`. Then return the interface.

## Where interfaces should live

**The consumer's package, not the producer's.** The interface describes
what the consumer needs; the producer doesn't know about consumers.

```go
// consumer (the user package):
package user

type Store interface {
    Get(ctx context.Context, id string) (*User, error)
    Put(ctx context.Context, u *User) error
}

func Service(s Store) *Svc { … }

// producer (somewhere else):
package mongo

func NewStore(client *mongo.Client) *MongoStore { … }
// MongoStore happens to satisfy user.Store; that's a runtime check, not a
// compile-time declaration in mongo's package.
```

If you find yourself defining a 10-method interface alongside one
implementation, move it. If you find yourself defining a 2-method
interface and there's only one implementation, consider deleting it.

## Interface size

Small interfaces compose; big interfaces dominate. The stdlib's
`io.Reader`, `io.Writer`, `io.Closer` are small for a reason: they're
useful in millions of unrelated contexts.

If your interface has > 4 methods, ask whether you can split it into
role-specific pieces. A `UserStore` with `Get`, `Put`, `List`, `Delete`,
`Count`, `Search`, `Subscribe`, `Audit` is 8 methods — split into
`UserReader`, `UserWriter`, `UserSearcher`, etc. and use embedding only
when the role-set genuinely groups together.

## Embedding interfaces

Composition over expansion:

```go
type ReadWriter interface {
    Reader
    Writer
}
```

This is *interface composition*. Don't confuse with struct embedding,
which forwards method calls to an embedded field — different concept.

## When generics make sense

Use type parameters when:

- The function operates on a container shape regardless of element type
  (`func Map[T, U any](s []T, f func(T) U) []U`).
- You'd otherwise need `interface{} / any` plus an unsafe type assertion.
- A constraint usefully expresses "any type with `<` ordering"
  (`constraints.Ordered`) or "any pointer type that implements an
  interface" (the constraint itself encodes the relationship).

```go
import "cmp"

func Min[T cmp.Ordered](xs ...T) T {
    m := xs[0]
    for _, x := range xs[1:] {
        if x < m { m = x }
    }
    return m
}
```

## When generics don't make sense

- The function works for one specific type. Just write it for that type.
- The function's caller-experience gets worse: they have to write
  `Foo[Bar](…)` in 90% of call sites because inference fails. That's a
  smell.
- The "abstraction" is a single wrapper around an interface method
  (`func Call[T Iface](t T)` adds nothing over `func Call(t Iface)`).
- Performance is the only motivation. Generics in Go are not zero-cost
  vs. interfaces in many real cases — measure first.

## Constraints

`any` (alias for `interface{}`) is the most general. Most useful named
constraints:

- `comparable` — supports `==` / `!=`. Required for map keys.
- `cmp.Ordered` — supports `< <= > >=`. Numbers and strings.
- Custom interface constraints — define an interface with the methods
  you need; that's the constraint.
- Type-set constraints with `|` — `type Number interface { ~int | ~float64 }`.
  The `~` means "any type whose underlying type is".

## Generics + interfaces gotchas

- A method on a generic type `(*Container[T]).Foo()` cannot itself
  introduce new type parameters. If you need that, make the method a
  free function.
- Type inference can fail in subtle places (type parameters appearing
  only in the return type). When inference fails, callers must specify
  explicitly — that's a usability cost. Restructure the API.
- An interface with a type-set constraint (`interface { ~int | ~float64 }`)
  is *not* an interface you can use as a value type. It only constrains
  type parameters. A regular method-only interface is both.

## A useful pattern: stamping out a type-safe map

```go
type Store[K comparable, V any] struct {
    mu sync.RWMutex
    m  map[K]V
}

func (s *Store[K, V]) Get(k K) (V, bool) {
    s.mu.RLock(); defer s.mu.RUnlock()
    v, ok := s.m[k]
    return v, ok
}

func (s *Store[K, V]) Put(k K, v V) {
    s.mu.Lock(); defer s.mu.Unlock()
    if s.m == nil { s.m = make(map[K]V) }
    s.m[k] = v
}
```

`Store[string, *User]` and `Store[int, []byte]` are now type-safe and
share the implementation. This is generics earning their keep.

## Anti-patterns

- **Defining `IUser`, `IStore`, `I…`** — Go convention is no `I` prefix.
  The interface is named for what it does (`Reader`, `UserStore`).
- **An interface for every struct.** "Mockability" is not a sufficient
  reason — most production code doesn't need mocks; it needs hand-rolled
  fakes. Define interfaces at the seams that matter.
- **Generics for "I want to write `func Get[T any](key string) T`"** —
  that signature can't be implemented; the function has to *return* a T,
  but it doesn't know how to construct one. You probably want a registry
  pattern with concrete types.
- **`any` everywhere a constraint would help.** If you're going to assert
  later anyway, try a constraint first.
