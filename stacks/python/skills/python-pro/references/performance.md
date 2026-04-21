# Python performance

Measure first. Every "optimization" without a profile is a guess.

## The profiling ladder

1. **Wall-clock first** — `time python app.py` or `hyperfine`. If it's fast
   enough, stop.
2. **`cProfile` / `profile`** — cumulative + own time per function. Good for
   sync workloads.
   ```bash
   python -m cProfile -o out.prof app.py
   python -m pstats out.prof     # then `sort cumulative`, `stats 30`
   ```
3. **`py-spy`** — sampling profiler, works on a running process, handles
   async stacks and C extensions. Start here for prod diagnosis.
   ```bash
   py-spy record -o flame.svg --pid <pid> --duration 30
   py-spy dump --pid <pid>
   ```
4. **`scalene`** — CPU + memory + GPU, line-level. Heavy in dev, great when
   you don't know if the issue is CPU or alloc.
5. **`memray`** — memory-focused tracer + flamegraph. Use for leaks or RSS
   creep.

Benchmarks: `pyperf timeit -s "setup" "stmt"` — robust (isolates the run,
filters noise, reports mean + stdev).

## Where wins usually are

| Symptom | Typical fix |
|---|---|
| "This loop is slow" | Vectorize (numpy), or hoist the dict lookup / attribute access out of the loop |
| `list` with `in` on large collections | Convert to `set` or `dict` |
| Repeated JSON parse of same file | `functools.lru_cache` or read once at startup |
| Creating millions of small objects | `@dataclass(slots=True, frozen=True)` or `__slots__`; consider `array` / `numpy` |
| String concat in a loop | `"".join([...])` or `io.StringIO` |
| Regex in hot path | Pre-compile (`re.compile(...)` at module level) |
| Global interpreter lock blocking CPU work | `ProcessPoolExecutor`, or a C extension (numpy, polars, rust via pyo3) |
| Slow startup | Defer imports inside functions; avoid heavy imports at module top |

## `__slots__` and dataclasses

`__slots__` cuts per-instance memory by ~50–70% and speeds attribute access
slightly.

```python
from dataclasses import dataclass

@dataclass(slots=True, frozen=True)
class Point:
    x: float
    y: float
```

Don't bother for classes you have < 10k of. Do bother for millions.

## Caching

```python
from functools import lru_cache, cache

@cache                         # unbounded, hashable args
def fib(n: int) -> int:
    return n if n < 2 else fib(n - 1) + fib(n - 2)

@lru_cache(maxsize=1024)       # bounded
def fetch_config(env: str) -> dict: ...
```

- Keys must be hashable. Converting lists to tuples at the boundary is fine.
- Beware caching on methods — `self` becomes part of the key. Use
  `@cached_property` for per-instance lazy values.

## Generators and `itertools`

For pipelines, chain generators — they stream and don't allocate the
intermediate list:

```python
from itertools import islice, takewhile

def process(path: Path) -> Iterator[Record]:
    with path.open() as f:
        for line in f:
            rec = parse(line)
            if rec.is_valid():
                yield rec

first_100 = list(islice(process(path), 100))
```

`itertools` primitives worth memorizing: `chain`, `islice`, `groupby`
(requires sorted input), `takewhile`, `dropwhile`, `accumulate`, `batched`
(3.12+).

## Concurrency vs. parallelism

- **I/O-bound**: `asyncio` for thousands of concurrent connections;
  `ThreadPoolExecutor` for a handful of blocking calls.
- **CPU-bound**: `ProcessPoolExecutor`, or a native library (numpy, polars,
  pyarrow, pydantic-core, orjson) — they release the GIL in their C code.
- **Mixed**: async event loop with `to_thread` for blocking edges and a
  process pool for occasional CPU work.

GIL-free CPython (PEP 703, 3.13 experimental) changes this, but don't design
around it yet in production.

## Serialization

- `orjson` is ~2–10× faster than stdlib `json` for dumps — use it in the hot
  path.
- `msgspec` is faster *and* does type-safe decoding — great for internal RPC.
- `pickle` for trusted in-process caches only. Never cross a trust boundary.
- `pyarrow` / `parquet` for tabular data that's read many times.

## When to escape Python

Symptom: you've profiled, you've batched, the hot loop is still slow.

- **numpy / polars** — for tabular / numeric work. Usually 10–100×.
- **Cython** — type-annotated `.pyx`, compiled to C. Ergonomic and still
  pip-installable. Best for algorithmic hotspots.
- **Rust via pyo3 / maturin** — safer than C, great for parsers, validators,
  anything CPU-bound and stateful.
- **Shelling out to a CLI** — last resort, but legitimate for one-shot
  compute (ffmpeg, GraphViz, etc.).

## Startup / import cost

Slow `python -c 'import myapp'` hurts CLI UX and cold-start latency in
serverless.

- `python -X importtime app.py` — shows import time per module, cumulative
  and self.
- Lazy imports for heavy deps:
  ```python
  def make_plot(df):
      import matplotlib.pyplot as plt    # imported only if called
      ...
  ```
- Avoid `__init__.py` that imports the whole package eagerly.

## Memory

- `tracemalloc` for a snapshot of where memory is allocated.
- `memray run --live app.py` for live flamegraph of allocations.
- Watch for: retained caches, growing dicts keyed by request ID without TTL,
  closures over large objects, `traceback`s stored in error handlers.
