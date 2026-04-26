# Ownership and lifetimes

The borrow checker rejects what's actually unsafe and lets you pass when
you've expressed the relationship correctly. The fix to "the borrow
checker is wrong" is almost always a different ownership shape, not a
workaround.

## The mental model

Three questions the compiler asks at every reference:

1. **Who owns this data?**
2. **How long does that owner live?**
3. **Are there outstanding borrows that must outlive me?**

If you can answer those three, you can usually predict the compiler's
verdict. When you're surprised, the surprise is data — go read what it
says.

## Owned vs borrowed

Default to **owned** in struct fields, function parameters that consume,
return types from constructors. Use **borrows** for read-only access
within a clear lifetime.

```rust
struct Config { url: String }       // owned, simple

fn parse(input: &str) -> Result<Config, Error> { … }  // borrows for reading

impl Config {
    fn url(&self) -> &str { &self.url }              // returns borrow tied to self
}
```

The biggest lifetime mistake: storing `&str` in a struct when you should
own `String`. The borrowed alternative requires every consumer to track
the lifetime — almost never worth it.

## When to spell lifetimes

The elision rules cover most cases. Spell lifetimes when:

1. The compiler asks ("expected lifetime parameter").
2. The function returns a borrow tied to a specific input ("this borrow
   comes from the second argument, not the first").
3. A struct holds a borrow.

```rust
// elided — fine, one input, output borrows from it
fn first(s: &str) -> &str { … }

// must spell — output ties to second arg
fn pick<'a>(_x: &str, y: &'a str) -> &'a str { y }

// must spell — struct holds a borrow
struct View<'a> { data: &'a [u8] }
```

Don't spell lifetimes "just to be safe". They're noise unless they
encode a real constraint.

## `'static`

`'static` means "lives for the entire program". Two distinct cases:

1. **Truly static data** — string literals (`&'static str`), `Box::leak`,
   `Lazy<T>`. Lifetime = program.
2. **`T: 'static` bound** — meaning "T does not borrow from anything
   non-static". `Vec<u8>` is `'static` because it owns. `&'a str` is not
   `'static` unless `'a == 'static`.

The bound case shows up in `tokio::spawn`:

```rust
tokio::spawn(async move {
    do_work(value).await    // value must be 'static (no borrows of stack data)
});
```

The fix is usually owned data (clone, Arc) rather than fighting it.

## `&` vs `&mut`

`&T` — shared, read-only, multiple allowed. `&mut T` — exclusive,
read/write, only one allowed at a time. They cannot coexist on the same
data.

When the borrow checker rejects `&mut self.field` because `self` is
borrowed elsewhere, the splits to consider:

1. **Field-level borrow** — `&mut self.field` while only borrowing
   `&self.other_field` is fine. Sometimes the issue is methods that
   take `&mut self` when they only mutate one field.
2. **Split borrows via destructuring** — `let Self { a, b } = self;`
   then borrow `a` and `b` independently.
3. **`std::mem::take`** — replace the field with the default, work on
   it, put it back. Useful when you need to consume + reassign.
4. **Two-phase borrows** are now allowed in many cases — the compiler
   delays the exclusive part of `&mut` until after the read part. Just
   try the natural code first.

## Smart pointers

| Pointer | Use when |
|---|---|
| `Box<T>` | Heap-allocate a single value. Trait objects. Recursive types. |
| `Rc<T>` | Shared ownership, single-threaded. Reference-counted. |
| `Arc<T>` | Shared ownership, thread-safe. Use over `Rc` in any async / threaded code. |
| `RefCell<T>` | Interior mutability, single-threaded. Runtime-checked. |
| `Mutex<T>` | Interior mutability, thread-safe. Lock-based. |
| `RwLock<T>` | Interior mutability, thread-safe, multi-reader. Heavier than `Mutex` for write-heavy workloads. |

Common combinations:

- `Arc<Mutex<T>>` — shared mutable state across threads. The default
  for tokio tasks sharing data.
- `Arc<T>` (without Mutex) — shared *immutable* data. Cheap.
- `Rc<RefCell<T>>` — shared mutable state in a single thread. Often a
  smell — usually the design wants ownership re-shuffled.

## `Cow<'_, T>` — clone on write

When a function sometimes needs to allocate and sometimes doesn't:

```rust
fn normalize(input: &str) -> Cow<'_, str> {
    if input.contains(' ') {
        Cow::Owned(input.replace(' ', "_"))
    } else {
        Cow::Borrowed(input)
    }
}
```

Useful in parsing, sanitization, and APIs where the caller may pass
already-clean input. Don't reach for `Cow` until you have a measured
reason — it adds a layer for the reader.

## Interior mutability rules

`RefCell`/`Mutex` borrow at runtime. Panicking on conflict.

```rust
let cell = RefCell::new(42);
let r1 = cell.borrow();
let r2 = cell.borrow_mut();   // PANIC at runtime — already borrowed
```

Always release `RefCell` borrows before another borrow attempt:

```rust
let val = *cell.borrow();     // borrow ends at end of expression
cell.borrow_mut().add_assign(val);
```

For `Mutex`, hold the guard for as little code as possible:

```rust
let val = {
    let guard = mutex.lock().unwrap();
    guard.compute()
};                            // guard dropped here
```

## Move semantics

`let y = x` *moves* `x` into `y` for non-`Copy` types. After the move,
`x` is invalid. The compiler tracks this.

```rust
let s = String::from("hi");
let t = s;                    // s moved into t
println!("{}", s);            // ERROR: s no longer valid
```

`Copy` types (integers, floats, bools, `&T`, fixed arrays of `Copy`)
are duplicated, not moved.

`Clone` is explicit duplication for non-`Copy` types: `let t = s.clone()`.

## Drop and destructors

`Drop::drop` runs when a value goes out of scope. Order: locals drop in
reverse declaration order; struct fields drop in declaration order.

Don't implement `Drop` for things that can be `Copy`. Don't `panic!` in
`drop` (causes double-panic / abort).

`std::mem::drop(value)` is the explicit "drop now" — useful for releasing
locks early, files, etc.

## The orphan rule and newtypes

You can implement a trait for a type only if you own the trait *or* you
own the type. Workaround: newtype.

```rust
struct MyVec(Vec<u8>);
impl Display for MyVec { … }    // legal — MyVec is yours
```

Newtypes are also useful for type-level invariants: `struct Email(String)`
where construction requires validation.

## Common borrow checker errors and what they mean

- **"cannot borrow `x` as mutable because it is also borrowed as
  immutable"** — there's still a `&x` outstanding when you try `&mut x`.
  Restructure so the immutable borrow ends first.
- **"`x` does not live long enough"** — you're returning a borrow whose
  source goes out of scope. Return an owned value or restructure
  ownership.
- **"`x` was moved here"** — you're using `x` after a move. Either
  borrow before the move, clone, or rearrange.
- **"`*self` is borrowed"** — you called a method that takes `&mut self`
  while another borrow of self existed. Split the work.
- **"closure may outlive the current function, but it borrows `x`"** —
  the closure needs `move` or owned data. `move` captures by value;
  may force a clone before the closure.

## When to reach for `unsafe`

Only when the safe alternatives are genuinely insufficient: FFI,
performance-critical primitives, `Pin` projection, low-level data
structures.

Every `unsafe` block needs a `// SAFETY:` comment explaining what
invariants the caller upholds. Test with `miri`.

```rust
// SAFETY: `ptr` is non-null and aligned per the contract of `from_raw`
// (we just received it from `into_raw` above; lifetime untouched).
unsafe { Box::from_raw(ptr) }
```

If you're writing more than a few lines of unsafe, isolate it in a
private module and expose a safe API. The hard part of `unsafe` is
designing the safe abstraction over it.
