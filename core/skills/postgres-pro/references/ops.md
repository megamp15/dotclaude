# Postgres operations

## Autovacuum — the thing that must not fall behind

Autovacuum does three jobs:

1. Reclaim space from dead tuples (MVCC row versions).
2. Update visibility map (enables Index Only Scans).
3. Prevent transaction ID wraparound.

Defaults are tuned for small DBs. For hot tables, override at the table
level:

```sql
ALTER TABLE events SET (
    autovacuum_vacuum_scale_factor = 0.02,   -- vacuum every +2% rows
    autovacuum_analyze_scale_factor = 0.01,
    autovacuum_vacuum_cost_limit = 2000       -- let autovac work harder
);
```

Monitor with:

```sql
SELECT
    relname,
    n_live_tup, n_dead_tup,
    n_dead_tup::float / GREATEST(n_live_tup, 1) AS dead_ratio,
    last_vacuum, last_autovacuum,
    last_analyze, last_autoanalyze
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

Dead ratio > 20% on a hot table is a signal. Something is blocking vacuum
(long transaction, replication slot behind, old snapshot) or thresholds
are too loose.

## Bloat

Table / index bloat happens when autovacuum can't keep up. Measure:

```sql
-- pgstattuple extension
SELECT * FROM pgstattuple_approx('public.events');
```

`dead_tuple_percent` or `free_space_percent` > ~30% is high. Remediation:

- Aggressive autovacuum settings (above).
- `VACUUM FULL` — rewrites the table, **exclusive lock**, downtime. Last
  resort.
- `pg_repack` — online equivalent; no downtime but requires the extension.
- For indexes: `REINDEX INDEX CONCURRENTLY`.

## Partitioning

For tables projected to be > ~100GB or with time-based retention.

Declarative partitioning (11+):

```sql
CREATE TABLE events (
    id bigint GENERATED ALWAYS AS IDENTITY,
    occurred_at timestamptz NOT NULL,
    payload jsonb NOT NULL,
    PRIMARY KEY (id, occurred_at)    -- partition key must be in PK
) PARTITION BY RANGE (occurred_at);

CREATE TABLE events_2026_04 PARTITION OF events
FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
```

Automate partition creation with `pg_partman`. Drop old partitions with
`DROP TABLE events_2024_01;` — instant, no mass `DELETE`.

Use range for time-series, hash for even distribution (multi-tenant with
many tenants), list for categorical (region, kind).

Rules:

- Every query should use the partition key in `WHERE` for pruning.
- Global uniqueness across partitions requires the partition key in the
  unique constraint.
- Cross-partition joins can be slow if partition-wise join isn't
  triggered — inspect plans.

## Connection pooling with `pgbouncer`

One Postgres connection ≈ 10MB RAM + backend process. A Node / Python app
opening 500 connections can OOM the DB.

Deploy `pgbouncer` in transaction mode:

- Apps connect to `pgbouncer` (cheap: it's a reverse proxy).
- `pgbouncer` keeps a small pool of real Postgres connections.
- Short transactions share the real connections efficiently.

Watch out for:

- **Session-level features break in transaction mode**: `SET`, `LISTEN`,
  temp tables, prepared statements (without `server_reset_query` /
  PgBouncer 1.21+ protocol-level prepared statement support).
- **`pg_advisory_lock(...)` (session-scoped)** — use
  `pg_advisory_xact_lock` instead.

## Logical replication

Row-level replication between Postgres instances:

```sql
-- Publisher
CREATE PUBLICATION orders_pub FOR TABLE orders;

-- Subscriber
CREATE SUBSCRIPTION orders_sub
    CONNECTION 'host=primary dbname=shop user=repl password=...'
    PUBLICATION orders_pub;
```

Use for:

- Zero-downtime major version upgrades.
- Moving to a new host or cloud.
- Feeding a read-only analytical replica.
- Table-level replication to a subset of tables.

Limitations:

- DDL is not replicated (you apply schema changes on both sides).
- Large objects (`bytea` is fine; `lo`-style LOBs are not).
- Sequences lag behind — resync after cutover.

## Backups

Two complementary strategies:

1. **Logical dumps** — `pg_dump` / `pg_dumpall`. Portable across versions.
   Slow to restore for large DBs, but perfect for daily snapshots and
   moving to a different engine.
2. **Physical / continuous** — `pg_basebackup` + WAL archiving. Fast
   restore, enables PITR (point-in-time recovery). Use
   [pgBackRest](https://pgbackrest.org) or [wal-g](https://github.com/wal-g/wal-g)
   in production.

Recovery target:

- **RPO** (how much data can you lose): depends on WAL archive cadence.
- **RTO** (how fast must you restore): depends on backup tool and
  parallelism.

Test restores. An untested backup is a rumor.

## Major-version upgrades

Options:

- **`pg_upgrade`** — in-place, fast, short downtime. Standard.
- **Logical replication** — zero-downtime; replicate to a new cluster,
  cut over.
- **Dump/restore** — simple, slow, downtime for the duration.

Pre-flight:

- Read the major version's release notes (breaking changes).
- Rebuild PostGIS / any extensions with native code.
- Refresh statistics after upgrade (`ANALYZE`).

## Monitoring — the cheap sheet

| Metric | What it catches |
|---|---|
| `pg_stat_activity` count, by state | Connection leaks, idle in transaction |
| `pg_stat_statements` top queries | Expensive queries, query regressions |
| `pg_stat_user_tables` n_dead_tup | Autovacuum falling behind |
| `pg_stat_replication.*_lag` | Replica falling behind |
| `pg_replication_slots.restart_lsn` | Stuck logical slots (eat disk) |
| `pg_stat_bgwriter` | Checkpoint health |
| Cache hit ratio | `shared_buffers` sizing |
| DB size growth | Partitioning / cleanup needed |

Ship these to your monitoring stack. Page on:

- Dead tuple ratio > 40% on a hot table.
- Replication lag > threshold.
- Connection count > 80% of `max_connections`.
- Transaction ID age > 80% of freeze threshold.
- Slow query avg latency regression.

## Configuration baseline

For a 32GB server:

```
shared_buffers = 8GB            # ~25% of RAM
effective_cache_size = 24GB     # ~75% of RAM (planner hint)
maintenance_work_mem = 2GB
work_mem = 32MB                 # per-operation; multiply by concurrent queries × sort operators
max_connections = 200
checkpoint_timeout = 15min
checkpoint_completion_target = 0.9
wal_compression = on
random_page_cost = 1.1          # SSDs
effective_io_concurrency = 200  # SSDs
default_statistics_target = 100
track_activities = on
track_counts = on
track_io_timing = on
shared_preload_libraries = 'pg_stat_statements'
```

Use [pgtune](https://pgtune.leopard.in.ua/) as a starting point; tune from
there with `pg_stat_statements` evidence.

## Extensions worth the install

| Extension | Purpose |
|---|---|
| `pg_stat_statements` | Per-query statistics. **Always on.** |
| `pgcrypto` | `gen_random_uuid()`, hashing, encryption |
| `pg_trgm` | Trigram (fuzzy) search |
| `citext` | Case-insensitive text |
| `hstore` | Key-value (`jsonb` is usually better) |
| `pgstattuple` | Bloat measurement |
| `pg_partman` | Partition management |
| `postgis` | Geospatial |
| `pgvector` | Vector similarity (for AI / RAG) |
| `timescaledb` | Time-series (has own operational model) |
