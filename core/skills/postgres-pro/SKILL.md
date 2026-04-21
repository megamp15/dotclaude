---
name: postgres-pro
description: PostgreSQL-specific expertise — schema design (JSONB vs columns, array types, enums, composite types), indexing (B-tree, GIN, BRIN, partial, covering, expression), query performance via `EXPLAIN (ANALYZE, BUFFERS)`, isolation / locking (MVCC, FOR UPDATE, advisory locks), partitioning, logical replication, and pragmatic tuning. Distinct from `sql-pro` (engine-agnostic query craft).
source: core
triggers: /postgres-pro, postgresql, psql, EXPLAIN ANALYZE, pg_stat_statements, GIN index, BRIN, jsonb, array type, partition, logical replication, pgbouncer, autovacuum, FOR UPDATE, advisory lock, row-level security
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/postgres-pro
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# postgres-pro

Deep PostgreSQL expertise — the things you only need when "Postgres", not
"relational database", is the answer. Covers schema modeling, indexing,
query plans, locking, and operational realities.

> **See also:**
>
> - `core/skills/sql-pro/` — engine-agnostic SQL craft (joins, CTEs, window
>   functions, normalization)
> - `core/rules/database.md` — cross-project DB conventions
> - `core/skills/api-designer/` — when the question is really "what's the
>   API contract"
> - `stacks/fastapi/skills/fastapi-expert/references/async-sqlalchemy.md` —
>   Postgres via async SQLAlchemy

## When to use this skill

- Choosing between a `jsonb` column, a side table, or an array of composite
  types.
- Picking the right index — and knowing why `WHERE a = ? AND b = ?` isn't
  using the one you thought.
- Reading `EXPLAIN (ANALYZE, BUFFERS)` output and knowing when a Seq Scan is
  actually fine.
- Diagnosing locking, deadlocks, and `SELECT … FOR UPDATE` waits.
- Partitioning a table that's now "too big to VACUUM in one go".
- Setting up logical replication, upgrade strategies, PITR.

## References (load on demand)

- [`references/schema-design.md`](references/schema-design.md) — column types
  (`jsonb` vs. relational, `uuid` vs. `bigint`, `text` vs. `varchar`, `numeric`
  for money), arrays, enums, constraints, generated columns.
- [`references/indexing.md`](references/indexing.md) — B-tree, GIN (jsonb /
  arrays / full-text), BRIN (append-only time series), partial indexes,
  covering indexes (`INCLUDE`), expression indexes, and what kills them.
- [`references/explain-and-perf.md`](references/explain-and-perf.md) — reading
  `EXPLAIN (ANALYZE, BUFFERS, VERBOSE)`, common operators (Seq / Index /
  Bitmap), estimate vs. actual gaps, `pg_stat_statements`, statistics
  (`ANALYZE`, `default_statistics_target`, extended stats).
- [`references/concurrency-and-locks.md`](references/concurrency-and-locks.md)
  — MVCC mental model, isolation levels, `FOR UPDATE` / `FOR NO KEY UPDATE` /
  `FOR SHARE`, advisory locks, deadlock detection, transaction id wraparound.
- [`references/ops.md`](references/ops.md) — autovacuum tuning, bloat,
  `pgbouncer` pooling, partitioning, logical replication, `pg_dump` /
  `pg_basebackup`, major-version upgrades, backup & PITR.

## Core workflow

1. **Know the Postgres version.** Major versions ship big perf and feature
   changes (partitioning overhaul in 11, `INCLUDE` in 11, JSON path in 12,
   parallel anything in 14+, MERGE in 15, logical replication row filters in
   15, incremental sort in 13, etc.). Ask before guessing.
2. **Measure with `EXPLAIN (ANALYZE, BUFFERS)`.** Never optimize without the
   plan. Never share a plan without `BUFFERS`.
3. **Schema first, then indexes, then queries.** A well-modeled table with
   one B-tree often beats a bad schema with six indexes.
4. **Mind the write cost.** Every index costs on insert/update/delete. GIN
   is especially expensive.
5. **Respect MVCC.** Long-running transactions stop autovacuum, bloat the
   heap, and break hot standby replicas. Transaction length is a core
   operational metric.

## Defaults

| Question | Default |
|---|---|
| Primary key for a new table | `id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY` (or `uuid` if distributed) |
| Money | `numeric(12, 2)` — never `float` / `double` |
| Timestamps | `timestamptz`, never `timestamp without time zone` |
| Short strings, no length limit | `text` (not `varchar(n)` unless you truly need the cap) |
| Enum-like small set | Postgres `ENUM` type *or* `text CHECK (col IN (...))` — latter is easier to evolve |
| Semi-structured blob | `jsonb`, indexed with GIN `jsonb_path_ops` if queried by path |
| Array of small set of values | native array, `int[]` / `text[]` |
| "Full-text search for one app" | `tsvector` + GIN, generated column for the vector |
| "Full-text search across the org" | Postgres FTS for a single DB; dedicated search engine (OpenSearch, Typesense) for cross-app |
| Multi-tenant isolation | Schema-per-tenant if < 100 tenants, row-level security with `tenant_id` if > 100 |
| Connection pooling | `pgbouncer` (transaction mode) in front of Postgres for apps with > 50 conn peaks |

## Anti-patterns

- **`SELECT *` in production queries.** You pay for every column you don't
  use, especially with wide rows and `TOAST`ed values.
- **`LIMIT 1` without `ORDER BY`.** Postgres is free to pick any row;
  "stable-looking" results are coincidence.
- **Client-side pagination with `OFFSET` on large tables.** Use keyset
  (`WHERE id > $last_id ORDER BY id LIMIT $n`).
- **`SELECT count(*)` as a health metric.** It's an `O(rows)` scan on
  Postgres (no stored count). Use an estimate from `pg_class.reltuples` if
  the exact number doesn't matter.
- **Indexes on every column.** Each index costs ~10–25% on writes. Drop
  unused indexes (`pg_stat_user_indexes.idx_scan = 0`).
- **Storing money in `float`.** Rounding loses you real money and real
  customers.
- **One giant `jsonb` blob replacing a real schema.** Use `jsonb` for
  variation, not to avoid modeling.
- **Long-running transactions.** Anything over a few seconds bloats the
  heap and holds replication slots. Chunk your batch jobs.
- **Trusting `ORDER BY` for sort stability without a tiebreaker.** Always
  include a unique column in the sort (`ORDER BY created_at DESC, id DESC`).

## Output format

For query perf questions:

```
Suspect plan:
  <offending node + cost + actual>

Why it's slow:
  <estimate mismatch / cold buffers / bad index / wrong join>

Fix attempts, in order:
  1. <cheapest: ANALYZE, index hint via statistics>
  2. <new / better index>
  3. <query rewrite>
  4. <schema change>

Verify:
  <re-run EXPLAIN ANALYZE; compare buffers>
```

For schema design:

```
Shape:
  <DDL snippet>

Indexes required:
  <list>

Read patterns it's good at:
  <list>

Read patterns it's bad at:
  <list + mitigation>

Write cost:
  <rough per-row cost, any triggers/constraints>
```
