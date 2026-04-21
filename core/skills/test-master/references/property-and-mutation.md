# Property-based testing and mutation testing

Two techniques that expose bugs example-based tests and coverage
metrics can't see.

## Property-based testing

### The idea

Instead of `assert reverse([1, 2, 3]) == [3, 2, 1]`, assert a
*property* that holds for **any** input:

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_reverse_twice_is_identity(xs: list[int]) -> None:
    assert reverse(reverse(xs)) == xs
```

Hypothesis generates hundreds of inputs (including edge cases like
`[]`, huge lists, negatives) and **shrinks** failures to the simplest
counterexample.

### When to reach for it

- **Parsers & serializers** — `parse(serialize(x)) == x`.
- **Compressor / encryptor round-trips** — same shape.
- **Commutativity / associativity** — `add(a, b) == add(b, a)`.
- **Idempotence** — `f(f(x)) == f(x)` (normalization).
- **Invariants** — sort result is monotonic; balanced tree stays
  balanced.
- **Data structures** — all ops preserve the class invariants.

### Common properties

| Category | Pattern |
|---|---|
| Round-trip | `decode(encode(x)) == x` |
| Inverse | `undo(do(x)) == x` |
| Idempotence | `f(f(x)) == f(x)` |
| Monotonicity | `a ≤ b → f(a) ≤ f(b)` |
| Commutativity | `f(a, b) == f(b, a)` |
| Associativity | `f(f(a, b), c) == f(a, f(b, c))` |
| Identity element | `f(a, id) == a` |
| Model equivalence | matches a simple reference implementation |

### Strategies

Hypothesis composes strategies:

```python
from hypothesis import given, strategies as st

user = st.builds(
    User,
    id=st.uuids(),
    email=st.emails(),
    age=st.integers(min_value=0, max_value=150),
)
```

For custom shapes, use `@st.composite`. For APIs, build schemas from
Pydantic models via `hypothesis-pydantic`.

### Shrinking

When a test fails, Hypothesis finds the *minimal* input that still
fails. Crucial: report messages are clean (e.g., `xs=[0, 0]` rather
than a random 4KB list).

### Limits & caveats

- **Slow by default** — run as a separate job or limit `@settings(max_examples=50)`
  locally, 200 in CI.
- **Stateful testing** for complex state machines via
  `RuleBasedStateMachine`.
- **Determinism** — set a fixed seed for reproducibility in CI.
- **Don't use for behavior with no invariants** — business rules
  with "customer X gets 10% off" are better as example tests.

### Fast-check (JavaScript/TypeScript)

```typescript
import fc from "fast-check";

test("sort is idempotent", () => {
  fc.assert(
    fc.property(fc.array(fc.integer()), (xs) => {
      const s = sort([...xs]);
      expect(sort([...s])).toEqual(s);
    }),
  );
});
```

Similar capabilities to Hypothesis.

### Other languages

- **Go** — `testing/quick` (built in, basic), `gopter` (richer).
- **Rust** — `proptest`, `quickcheck`.
- **Java/Kotlin** — `jqwik`.
- **C#** — `FsCheck`.

## Mutation testing

### The idea

Mutation testing injects small bugs ("mutants") into your source,
reruns the suite, and reports how many mutants were *caught* (a test
failed) vs. *survived* (all tests still pass).

A surviving mutant = dead test coverage — the code path was executed
but nothing asserted on it.

### Example mutations

- Arithmetic operator swap: `+` → `-`
- Comparison swap: `<` → `<=`
- Boundary shift: `x > 0` → `x >= 0`
- Boolean literal swap: `True` → `False`
- Return value deletion: `return x` → `return None`
- Condition negation: `if x:` → `if not x:`

### Tools

| Language | Tool |
|---|---|
| Python | `mutmut`, `cosmic-ray` |
| JS/TS | `Stryker` |
| Java | `PIT` (pitest) — the gold standard |
| Go | `go-mutesting`, `gremlins-rs` |
| Rust | `cargo-mutants` |
| C# | `Stryker.NET` |

### Running mutmut

```bash
uv run mutmut run --paths-to-mutate=src/
uv run mutmut results
uv run mutmut show 3        # inspect mutant #3
```

### Interpreting results

- **Killed** — tests failed. Good.
- **Survived** — tests pass despite the mutation. A gap.
- **Timeout** — mutation caused infinite loop. Usually "caught".
- **Suspicious** — flaky mutation (probably fine).
- **Skipped** — typically equivalent mutation (syntax-only change).

### What to do with survivors

For each surviving mutant:

1. **Add a test** that fails on the mutation → re-run → killed.
2. **Declare it dead code** → delete it.
3. **Mark it as equivalent** (semantically identical to original) if
   the tool supports it.

### Scope and schedule

Mutation testing is **expensive** (N×suite runtime where N = number
of mutants). Practical strategy:

- **Nightly CI**, not PR gate.
- Scope to critical modules (money, auth, parsers, domain core).
- Target **60–80% mutation score** on those modules.
- Track trend, not absolute number.

### Mutation testing vs. coverage

Line coverage says "this line ran". Mutation testing says "this line
is **actually checked**".

Example:

```python
def is_adult(age: int) -> bool:
    return age >= 18

def test_adult() -> None:
    assert is_adult(30) is True
```

Line coverage: 100%.

Mutant: `age >= 18` → `age > 18`. Test still passes (30 > 18). **Bug
shipped**: an 18-year-old is not an adult per this mutation.

Fixing:

```python
def test_exact_boundary() -> None:
    assert is_adult(18) is True
    assert is_adult(17) is False
```

Now the mutation kills the test. Coverage was lying.

## Combining the two

Property-based tests often kill mutations that example-based tests
don't — because they exercise the boundaries automatically.

Workflow:

1. Write example-based tests for the happy path and known edge cases.
2. Add property-based tests for invariants.
3. Run mutation testing. Address survivors.
4. Repeat at refactor time to keep the test suite honest.

## Anti-patterns

- **Property tests with `assume` everywhere** — you're narrowing the
  domain so much that it's an example test in disguise. Loosen the
  strategy or test a different property.
- **Pinning to Hypothesis's generation** — if a test depends on the
  library's exact shrinking algorithm, it's brittle.
- **Ignoring mutation survivors en masse** — either the test suite
  is inadequate or the tool is misconfigured. Don't set a suppress
  list as a first reaction.
- **Running mutation testing on all code, always** — too slow;
  people turn it off. Scope it.
