# `EXPLAIN` and query performance

## The invocation

```sql
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, FORMAT TEXT)
SELECT ...
```

- `ANALYZE` — actually runs the query and reports actual times. Will side-effect on writes. Wrap DML in a transaction you roll back.
- `BUFFERS` — shows shared / local / temp buffer hits and reads. Without this, you're guessing.
- `VERBOSE` — includes output columns and schema-qualified names.
- `SETTINGS` — lists any non-default GUC settings that may have affected the plan.
- `FORMAT JSON` — machine-readable, great for tools like [explain.dalibo.com](https://explain.dalibo.com/) and [pev2](https://dalibo.github.io/pev2/).

## The hierarchy

Read bottom-up. Each node's actual time includes its children; subtract to
get per-node cost.

```
Seq Scan on users (cost=0..1234 rows=10000 width=32) (actual time=0.01..12.3 rows=9876 loops=1)
  Buffers: shared hit=123 read=456
```

- `cost` — planner's estimate (arbitrary units, roughly scaled to disk page reads). First number is "cost to first row"; second is "total".
- `rows` — estimated rows vs. `actual rows`. **The single biggest tell.** If estimate is 100× off, stats are stale or the predicate is hard to estimate.
- `width` — avg row size in bytes.
- `actual time` — ms for first row, ms to finish, for one loop.
- `loops` — how many times this node ran (nested loops run the inner subplan `loops` times).
- `Buffers: shared hit` — cache hits (RAM). `read` — cache misses (disk).

## Operators to know

| Operator | Good | Bad |
|---|---|---|
| **Seq Scan** | Small table; no useful index; the planner wants most rows anyway | Large table + WHERE clause that should filter most rows |
| **Index Scan** | Selective WHERE; ORDER BY matches index | "Rows Removed by Filter" is most of them — index is doing less than it looks |
| **Index Only Scan** | Covering index + up-to-date visibility map | `Heap Fetches: <high>` means VM is stale — run `VACUUM` |
| **Bitmap Index Scan + Bitmap Heap Scan** | Mid-selectivity, multi-col unions | If two bitmap scans get AND'd, maybe one composite index is better |
| **Nested Loop** | Small outer side (< ~1000 rows), indexed inner lookup | Big outer side — should be Hash or Merge |
| **Hash Join** | Mid / large tables, fits in `work_mem` | Builds a hash that spills to disk → look for "Batches: >1, Memory Usage" |
| **Merge Join** | Both sides already sorted by join key | Requires sort otherwise |
| **Sort** | Needed for ORDER BY / Merge Join | If `work_mem` too small, spills ("external merge Disk") |
| **Gather / Parallel Seq Scan** | Big table, multi-core | Tiny tables — parallel setup cost > savings |

## Estimate vs. actual

Large gaps between estimated and actual rows = bad plans. Causes:

- **Stale stats.** Run `ANALYZE <table>;`. Consider raising
  `default_statistics_target` (default 100) for hot tables' hot columns.
- **Correlated columns.** Postgres assumes independence. If `state` and
  `country` correlate (all "Paris" rows are in France), use extended
  statistics:
  ```sql
  CREATE STATISTICS ext_stats ON state, country FROM addresses;
  ANALYZE addresses;
  ```
- **Expression in predicate.** `WHERE lower(email) = '...'` has no
  statistics on `lower(email)`. Use an expression index.
- **Skewed data.** Most-common-values list caps at
  `default_statistics_target`. Rare values are treated as one bucket.

## `pg_stat_statements`

Enable it (`shared_preload_libraries = 'pg_stat_statements'` + create the
extension). Then:

```sql
SELECT
    queryid,
    calls,
    total_exec_time,
    mean_exec_time,
    stddev_exec_time,
    rows,
    query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 20;
```

This is where you find the queries worth tuning. `mean_exec_time > 50ms` or
`calls * mean_exec_time > total_exec_time_of_top_10 * 0.1` deserves a look.

## Reading a slow plan

1. **Is any node's `actual time` most of the total?** That's the bottleneck.
2. **Does any node have `actual rows` >> `estimated rows`?** Stats /
   correlation problem.
3. **`Buffers: shared read` high?** Cache miss. Either the dataset is big,
   or the first run wasn't warmed up. Compare first-run vs. second-run.
4. **Sort / Hash with `Disk: N kB`?** `work_mem` too small for this query.
   Raise at session level (`SET LOCAL work_mem = '256MB'`) or system level.
5. **Nested Loop with big outer side?** Often a missing index on the inner
   join key, or the optimizer made the wrong shape choice — try `SET
   enable_nestloop = off;` to see what else is possible.

## Session-level perf levers

Use sparingly, with `SET LOCAL` inside a transaction:

| GUC | Purpose |
|---|---|
| `work_mem` | Per-operation sort/hash memory |
| `maintenance_work_mem` | `CREATE INDEX`, `VACUUM` budget |
| `enable_seqscan` | `off` forces index plans (diagnosis only) |
| `enable_nestloop` | `off` explores other join shapes (diagnosis only) |
| `random_page_cost` | Lower for SSDs (1.1 is common) — affects plan shape |
| `effective_cache_size` | Let planner know ~RAM available for disk cache |
| `jit` | Turn off for short queries on JIT-heavy Postgres 11+ — can cost more than it saves |

## Warming the cache

Before benchmarking:

```sql
SELECT pg_prewarm('users');       -- pg_prewarm extension
```

Or run the query twice and take the second timing. Cold-cache numbers are
for ops and capacity planning, warm-cache for query tuning.

## Common wins by symptom

| Symptom | Fix |
|---|---|
| Nested Loop with > 1M outer rows | Force Hash Join (stats fix, or add index on join col) |
| Sort: external merge Disk: 1.2GB | `SET LOCAL work_mem = '...'` for that session |
| Index Only Scan with Heap Fetches: millions | `VACUUM` the table; visibility map stale |
| Large Rows Removed by Filter | Index doesn't cover the predicate — add / adjust index |
| Estimate 1 row, actual 1M | Stats wrong — `ANALYZE` + possibly extended stats |
| Bitmap Heap Scan reads most of the table | Index not selective enough; use Seq Scan or restructure |
| Parallel plan slower than serial | Force `max_parallel_workers_per_gather = 0` for this query, or raise `min_parallel_table_scan_size` |

## Diagnostic transactions pattern

```sql
BEGIN;
SET LOCAL work_mem = '256MB';
EXPLAIN (ANALYZE, BUFFERS) <query>;
ROLLBACK;
```

The `ROLLBACK` undoes any side effects of `ANALYZE`-running writes or
advisory locks.
