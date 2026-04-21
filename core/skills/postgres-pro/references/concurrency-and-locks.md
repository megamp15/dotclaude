# Concurrency and locks

## MVCC in one paragraph

Every row has an `xmin` (transaction that created it) and `xmax` (transaction
that deleted it). Each query sees only the rows visible at its snapshot.
Updates write a new version; the old version stays until no transaction
can see it and autovacuum reclaims it. This is why long transactions cause
bloat — they hold snapshots that keep old row versions alive.

## Isolation levels

| Level | Postgres behavior |
|---|---|
| **Read Committed** (default) | Each statement sees committed data as of its start |
| **Repeatable Read** | Each transaction sees a snapshot as of its first read; concurrent updates to rows it read fail with `serialization_failure` |
| **Serializable** | Like Repeatable Read + read-write and write-read conflicts also fail; logically equivalent to one-transaction-at-a-time |

Pick:

- **Read Committed** — default, fine for most OLTP.
- **Repeatable Read** — financial / accounting reads that need a stable view.
- **Serializable** — when correctness trumps throughput. Be ready to retry on
  `serialization_failure` (SQLSTATE `40001`).

Set per transaction:

```sql
BEGIN ISOLATION LEVEL SERIALIZABLE;
```

## Row locks: `FOR UPDATE` family

```sql
-- Row-level exclusive, blocks anyone trying to UPDATE or SELECT FOR UPDATE
SELECT * FROM accounts WHERE id = $1 FOR UPDATE;

-- Weaker: just blocks UPDATE of the primary key / FK-referenced columns
SELECT * FROM accounts WHERE id = $1 FOR NO KEY UPDATE;

-- Shared: multiple reads OK, blocks writes
SELECT * FROM accounts WHERE id = $1 FOR SHARE;

-- Key share: weakest — blocks only DELETE and changes to keys
SELECT * FROM accounts WHERE id = $1 FOR KEY SHARE;

-- Skip already-locked rows (queue worker pattern)
SELECT * FROM tasks WHERE status = 'pending'
ORDER BY id FOR UPDATE SKIP LOCKED LIMIT 1;

-- Fail instead of waiting
SELECT * FROM accounts WHERE id = $1 FOR UPDATE NOWAIT;
```

**`FOR UPDATE SKIP LOCKED`** is how you build a safe queue on Postgres
without a dedicated queue system. Workers grab one row, skip any row being
processed, and commit at the end.

## Advisory locks

Application-level locks Postgres coordinates for you:

```sql
-- Blocking lock within a session
SELECT pg_advisory_lock(12345);
-- ... critical section
SELECT pg_advisory_unlock(12345);

-- Try once, never block (great for cron / singletons)
SELECT pg_try_advisory_lock(12345);

-- Transaction-scoped (released on COMMIT/ROLLBACK, no unlock needed)
SELECT pg_advisory_xact_lock(12345);
```

Use for:

- "Only one instance of this job at a time" (hash the job name to an int).
- Coordinating a migration across multiple nodes.
- Serializing a critical operation without creating a lock table.

Pick unique keys (two 32-bit ints or one 64-bit int) and document them.

## Upsert with conflict

```sql
INSERT INTO counters (id, count)
VALUES ($1, 1)
ON CONFLICT (id)
DO UPDATE SET count = counters.count + 1
RETURNING count;
```

`ON CONFLICT DO UPDATE` (upsert) is atomic. Requires a unique or exclusion
constraint on the conflict columns.

## Deadlocks

Deadlock:

1. Tx A locks row 1, tries to lock row 2.
2. Tx B locks row 2, tries to lock row 1.

Postgres detects this after `deadlock_timeout` (default 1s), kills one
transaction with `ERROR: deadlock detected`.

Avoid:

- **Always lock in the same order.** Sort by ID before locking multiple
  rows.
- **Keep transactions short.** Fewer opportunities for conflict.
- **Prefer `SELECT FOR UPDATE` over gradually escalating locks.**
- **Watch batch updates** — a batch that locks 100k rows in random order is
  a deadlock factory.

## Lock visibility

```sql
SELECT
    pid,
    state,
    wait_event_type, wait_event,
    age(clock_timestamp(), query_start) AS running_for,
    query
FROM pg_stat_activity
WHERE state != 'idle';

-- Who holds what locks
SELECT
    l.pid,
    l.mode,
    l.granted,
    c.relname AS object,
    a.query,
    age(clock_timestamp(), a.query_start) AS age
FROM pg_locks l
LEFT JOIN pg_class c ON c.oid = l.relation
JOIN pg_stat_activity a ON a.pid = l.pid
WHERE NOT l.granted
ORDER BY age DESC;
```

For blocker-blocked pairs, use `pg_blocking_pids(pid)`.

## Idle in transaction

A session left "idle in transaction" holds its snapshot and any locks
forever. Kill with:

```sql
SELECT pg_cancel_backend(pid);     -- graceful, cancels current query
SELECT pg_terminate_backend(pid);  -- hard kill the connection
```

Prevent with `idle_in_transaction_session_timeout = '5min'` on Postgres 12+.

## Long transaction early warning

```sql
SELECT
    pid,
    usename,
    age(clock_timestamp(), xact_start) AS xact_age,
    state,
    query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_age DESC
LIMIT 10;
```

Anything older than a few minutes is worth investigating. Anything older
than an hour is a problem.

## Transaction ID wraparound

Postgres transaction IDs are 32-bit. Without vacuuming, you can run out —
the DB goes read-only to protect itself. Autovacuum prevents this, but:

```sql
SELECT datname, age(datfrozenxid)
FROM pg_database
ORDER BY age(datfrozenxid) DESC;
```

If any age approaches `autovacuum_freeze_max_age` (default 200M), something
is blocking vacuum. Usually a long-open transaction (replication slot,
abandoned prepared transaction, idle in transaction connection).

## Optimistic locking

App-level concurrency control — avoids DB locks for read-mostly workloads:

```sql
UPDATE posts
SET title = $1, version = version + 1
WHERE id = $2 AND version = $3;
```

If `UPDATE` returns 0 rows, someone else beat you — reload and retry.
Great when conflicts are rare.
