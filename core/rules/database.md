---
name: database
description: Universal data safety — migrations, transactions, consistency. SQL and NoSQL.
source: core
alwaysApply: false
triggers: migration, alembic, prisma migrate, flyway, liquibase, drop table, alter table, schema change, transaction
---

# Database

High-consequence. Get this wrong and you lose data. These rules apply
regardless of engine (Postgres, MySQL, SQLite, MongoDB, DynamoDB).

## Migrations

- **Every migration is tested against a copy of production-shaped data** before it runs on production.
- **Every migration is reversible** or has a documented recovery path. If it isn't reversible, it's a coordinated deploy — get the plan reviewed.
- **Never edit a migration that has run in production.** Create a new one that fixes the mistake. Rewriting history breaks teammates' local DBs and any environments that already applied the old version.
- **One logical change per migration.** Mixing "rename column + backfill + drop old column" is three migrations deployed in sequence, not one.

### The expand/contract pattern

For any breaking schema change, split into three deploys:

1. **Expand** — add the new shape alongside the old. Code writes to both, reads from old.
2. **Migrate** — backfill the new shape. Switch reads to new. Old still written for safety.
3. **Contract** — stop writing old, then drop it.

Skipping any step means a window where a rollback breaks.

### Rename, delete, tighten constraints

- **Rename a column:** add new, dual-write, backfill, switch reads, stop writing old, drop. Never a single `ALTER TABLE ... RENAME` across a deploy boundary.
- **Drop a column:** stop reading, stop writing, deploy, drop in a later migration. Never drop in the same deploy that removes the reads.
- **Add `NOT NULL`:** add as nullable, backfill, then add the constraint. Adding `NOT NULL` on a column with any NULLs fails the migration.
- **Add unique constraint:** same flow. Deduplicate first, then add the constraint.
- **Change column type:** expand/contract via a new column.

### Dangerous operations (always flag, sometimes block)

- `DROP TABLE`, `DROP DATABASE`, `DROP SCHEMA`.
- `TRUNCATE`.
- `DELETE FROM table;` without `WHERE`.
- `UPDATE table SET ...;` without `WHERE`.
- Altering primary keys.
- Dropping indexes on large tables without replacement during high traffic.

## Transactions

- **Wrap multi-statement writes in a transaction.** Partial success with no rollback corrupts data.
- **Don't hold a transaction across an external call.** An HTTP call inside a DB transaction means the DB row is locked while a third party may take 30 seconds to respond. Classic deadlock setup.
- **Keep transactions short.** Long transactions hold locks, block other work, and blow up replication lag.
- **Choose isolation level intentionally.** The default is rarely the right answer for high-concurrency writes. Know what your engine's default is.
- **Use `SELECT FOR UPDATE` (or equivalent) for read-then-write patterns** where two transactions racing could both think they're the first writer.

## Concurrency

- **Unique constraints at the DB level** — not only in application code. Two requests can race past an app check.
- **Optimistic locking** via a version column for update-heavy rows. Reject writes with stale versions; caller retries.
- **Idempotency keys** for write endpoints that clients might retry. The DB enforces "don't do it twice" based on the key.

## Queries

- **Always bound results.** `LIMIT` on every list query. Paginate by cursor, not offset, for large tables.
- **Explain before merging** any query on a table over ~100k rows. Verify it uses the right index.
- **No `SELECT *`** in production code. List the columns. Adds a dependency you didn't mean to add.
- **No ORM lazy-load across request boundaries.** Serializing inside a template or response builder triggers one query per row.
- **N+1 is a bug.** Fetch related data eagerly or batch.

## Deletions

- **Soft delete by default** for user-facing data. Recovery is asked for often enough that hard deletes are a liability.
- **Hard deletes are fine for:** idempotency keys past their window, old audit rows past retention, bot-generated spam after review.
- **Cascade deletes are a landmine.** Know exactly what deleting a parent removes. Document it. Test it.

## Testing

- **Use a real DB engine in tests** where feasible (testcontainers, ephemeral instance). SQLite-as-fake-for-Postgres hides real bugs.
- **Roll back every test.** Tests that commit pollute each other and themselves.
- **Test the migration itself** — apply, assert, apply again (should be a no-op), roll back (if reversible).

## Backups

- Know your backup cadence. Know your restore time. **Test the restore.** Untested backups are hope.
- Before any risky migration: point-in-time snapshot or equivalent.
- Migration + rollback + restore-from-backup = three layers of defense. Have at least two.

## NoSQL-specific

- **Key design is schema design.** Bad keys make ranges impossible and scans expensive. Design for your read patterns first.
- **Eventual consistency is a feature, not a bug — but know when you need strong.** Read-your-writes, monotonic reads, transaction-like operations all have specific knobs in each engine.
- **Item size limits matter.** 400KB in DynamoDB, 16MB in MongoDB. Plan for growth or shard explicitly.
