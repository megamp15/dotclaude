# Advanced Python typing

Python 3.11+ typing tools worth reaching for, with the gotchas that make
`mypy --strict` pass.

## `TypedDict` for structured dicts

Use when the *shape* is dict (JSON from an API, kwargs forwarding) but you
want structural type-checking.

```python
from typing import TypedDict, NotRequired

class UserDTO(TypedDict):
    id: int
    email: str
    name: NotRequired[str]           # optional key, not "value may be None"
    created_at: str
```

- `NotRequired[T]` = key may be absent (preferred over `total=False` + `Required[...]`).
- `TypedDict` is a dict at runtime — no validation. Use `pydantic` if you need
  parsing.
- Subclass to extend: `class AdminDTO(UserDTO): role: str`.

## `Protocol` for duck typing

Use when you want "anything shaped like this" without forcing inheritance —
especially across a library/consumer boundary.

```python
from typing import Protocol

class SupportsClose(Protocol):
    def close(self) -> None: ...

def shutdown(resource: SupportsClose) -> None:
    resource.close()
```

- Add `@runtime_checkable` *only* if you need `isinstance(x, Protocol)`. It's
  slower and weaker (only checks attribute presence, not signatures).
- Protocols compose: `class ReadWriteClose(SupportsRead, SupportsWrite, SupportsClose): ...`.

## Generics the right way

```python
from typing import TypeVar, Generic

T = TypeVar("T")
K = TypeVar("K")
V = TypeVar("V")

class Cache(Generic[K, V]):
    def get(self, key: K) -> V | None: ...
    def put(self, key: K, value: V) -> None: ...
```

Bounded:

```python
from typing import TypeVar

NumberT = TypeVar("NumberT", bound=int | float)

def clamp(value: NumberT, lo: NumberT, hi: NumberT) -> NumberT:
    return max(lo, min(value, hi))
```

`Self` for fluent builders:

```python
from typing import Self

class Query:
    def where(self, clause: str) -> Self: ...
    def limit(self, n: int) -> Self: ...
```

## `@overload` for callers that depend on argument shape

```python
from typing import overload, Literal

@overload
def fetch(id: int, *, raw: Literal[True]) -> bytes: ...
@overload
def fetch(id: int, *, raw: Literal[False] = False) -> dict[str, object]: ...
def fetch(id: int, *, raw: bool = False) -> bytes | dict[str, object]:
    body = _load(id)
    return body if raw else json.loads(body)
```

- Order overloads from most specific to least specific.
- The actual implementation signature goes last and uses the union.

## `ParamSpec` and `Concatenate` for decorators

```python
from typing import ParamSpec, TypeVar, Callable
from functools import wraps

P = ParamSpec("P")
R = TypeVar("R")

def timed(fn: Callable[P, R]) -> Callable[P, R]:
    @wraps(fn)
    def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
        start = time.monotonic()
        try:
            return fn(*args, **kwargs)
        finally:
            logger.info("elapsed", extra={"fn": fn.__qualname__, "ms": (time.monotonic() - start) * 1000})
    return wrapper
```

For "first arg injected" decorators (e.g., passing a DB session in):

```python
from typing import Concatenate

def with_session(fn: Callable[Concatenate[Session, P], R]) -> Callable[P, R]: ...
```

## `Literal` + discriminated unions

```python
from typing import Literal

class Success(TypedDict):
    status: Literal["ok"]
    data: dict[str, object]

class Failure(TypedDict):
    status: Literal["error"]
    message: str

Response = Success | Failure

def handle(r: Response) -> str:
    match r["status"]:
        case "ok":
            return str(r["data"])
        case "error":
            return r["message"]
```

`match` narrows in both directions when the discriminant is `Literal`.

## `Unpack` for typed `**kwargs`

```python
from typing import Unpack, TypedDict

class HTTPKwargs(TypedDict, total=False):
    timeout: float
    retries: int
    headers: dict[str, str]

def request(url: str, **kwargs: Unpack[HTTPKwargs]) -> Response: ...
```

## `mypy --strict` survival

Common ways `--strict` trips you:

- **Untyped decorator wrapping** — use `ParamSpec` as above.
- **Module-level `None`** — `x: list[int] = []` not `x = []`.
- **Third-party libs without stubs** — add `[[tool.mypy.overrides]]` blocks with
  `ignore_missing_imports = true` for the specific module, not globally.
- **Mixing `Any`** — treat every `Any` as a TODO. Search for `: Any` before PR.
- **Returning `NotImplemented`** — use `@abstractmethod` and don't type-hint it
  as the concrete return type.

## Testing for type-level behavior

Use `assert_type` (Python 3.11+) to make type tests run under mypy:

```python
from typing import assert_type

result = fetch(1)
assert_type(result, dict[str, object])
```

## Quick decisions

| You want to express | Use |
|---|---|
| "This parameter is one of {a, b, c}" | `Literal["a", "b", "c"]` |
| "This dict has known keys" | `TypedDict` |
| "Anything with a `close()` method" | `Protocol` |
| "Pass all args through" (decorator) | `ParamSpec` |
| "Heterogeneous *args" (e.g. tuple) | `TypeVarTuple` + `Unpack` |
| "Return the same subclass I was called on" | `Self` |
| "Overload-shaped callable" | `@overload` |
| "I don't want nullability ambiguity" | `X \| None`, never bare `None` in params |
