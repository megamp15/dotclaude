# Indexing

The decision isn't "do I need an index" — it's "which kind, over what, and
is it worth the write cost".

## Index types at a glance

| Type | Good for | Not for |
|---|---|---|
| **B-tree** (default) | `=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `IN`, `IS NULL`, `ORDER BY`, prefix `LIKE 'x%'` | substring search, jsonb path |
| **Hash** | `=` only, hashable types | range queries |
| **GIN** | `jsonb`, arrays, FTS (`tsvector`), `ltree` | range / ordering |
| **BRIN** | Append-only, physically ordered data (time series) | random-access workloads |
| **GiST** | Geometric, range types, FTS, ES similarity (`pg_trgm` GIST) | equality on huge domains (GIN is faster for FTS) |
| **SP-GiST** | Non-balanced trees (phone prefixes, IP ranges) | anything else |

## B-tree essentials

### Multi-column order matters

Index `(a, b, c)` can serve:

- `WHERE a = ?`
- `WHERE a = ? AND b = ?`
- `WHERE a = ? AND b = ? AND c = ?`
- `WHERE a = ? ORDER BY b`

It cannot serve `WHERE b = ?` alone. The leftmost prefix rule.

Put the **most selective equality column first**. Range columns last (because
B-tree is ordered on prefix + a range at the leaf breaks further usefulness).

### Partial indexes

Index only the rows that matter:

```sql
CREATE INDEX users_email_active_idx ON users (email)
WHERE deleted_at IS NULL;

CREATE INDEX orders_pending_idx ON orders (created_at)
WHERE status = 'pending';
```

Massive wins when the hot query always filters on a small subset of the
table.

### Covering indexes (`INCLUDE`)

Include columns in the leaf without making them sortable — enables
index-only scans:

```sql
CREATE INDEX posts_author_covering ON posts (author_id)
INCLUDE (title, published_at);

-- This can be served entirely from the index (no heap fetch):
SELECT title, published_at FROM posts WHERE author_id = $1;
```

Requires the table's visibility map to be current (run `VACUUM` after big
changes). Check `EXPLAIN` for `Heap Fetches: 0` to confirm.

### Expression indexes

Index a computed expression:

```sql
CREATE UNIQUE INDEX users_lower_email_idx ON users (lower(email));

SELECT * FROM users WHERE lower(email) = lower('Alice@Example.com');
```

The query has to match the expression exactly. Store the normalized form as
a generated column if you don't want to repeat the expression.

## GIN — the right default for jsonb, arrays, and FTS

```sql
-- jsonb with path query support only (smaller, faster)
CREATE INDEX events_payload_path ON events USING gin (payload jsonb_path_ops);

-- jsonb with full flexibility (containment + key-exists)
CREATE INDEX events_payload_full ON events USING gin (payload);

-- Array containment
CREATE INDEX posts_tags_gin ON posts USING gin (tags);

-- Full-text
ALTER TABLE articles ADD COLUMN tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', body)) STORED;
CREATE INDEX articles_tsv_idx ON articles USING gin (tsv);
```

GIN trade-off: fast reads, **slow writes** (each row update can touch many
index entries). Mitigate with `fastupdate = on` + tuned `gin_pending_list_limit`
for write-heavy tables.

## BRIN — for the one-massive-table case

BRIN stores min/max per block range. Tiny (a few KB for GBs of data),
effective when data is physically ordered on the indexed column.

Perfect for time-series append-only tables:

```sql
CREATE INDEX events_occurred_brin ON events USING brin (occurred_at)
    WITH (pages_per_range = 64);
```

Useless if inserts are random or the table gets a lot of updates (MVCC
versions get out of order).

## Trigram indexes (`pg_trgm`)

For substring search / fuzzy match:

```sql
CREATE EXTENSION pg_trgm;

CREATE INDEX users_name_trgm ON users USING gin (name gin_trgm_ops);

-- Now:
SELECT * FROM users WHERE name ILIKE '%alice%';
SELECT * FROM users WHERE name % 'Alyce';   -- similarity operator
```

## Index only for queries that run

Before you add an index, answer:

1. What's the query?
2. What's the plan today? (`EXPLAIN ANALYZE`)
3. How often does it run?
4. What's the write rate on this table?

An index that speeds up a query run 100/day by 10ms, but slows down 10k
inserts/day by 1ms each — you just lost time.

## Finding dead weight

```sql
-- Unused indexes (idx_scan = 0 means nothing has hit this since stats reset)
SELECT schemaname, relname, indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- Duplicate indexes
SELECT
    pg_size_pretty(SUM(pg_relation_size(idx))::bigint) AS size,
    (array_agg(idx))[1] AS idx1,
    (array_agg(idx))[2] AS idx2
FROM (
    SELECT indexrelid::regclass AS idx,
           (indrelid::text || E'\n' || indclass::text || E'\n' ||
            indkey::text || E'\n' || coalesce(indexprs::text, '') || E'\n' ||
            coalesce(indpred::text, '')) AS KEY
    FROM pg_index
) sub
GROUP BY KEY
HAVING COUNT(*) > 1;
```

## Bloat and reindexing

Indexes bloat over time (especially with heavy updates). Signs:

- `pg_class.relpages` much larger than needed.
- `pgstattuple_approx` or `pgstatindex` reports high dead space.

Fix without downtime:

```sql
REINDEX INDEX CONCURRENTLY users_email_idx;   -- no lock held
```

## When an index won't help

- Function wrapping the column: `WHERE lower(email) = 'x'` misses
  `(email)` index. Solution: expression index.
- Type mismatch: `WHERE id = '42'` on an integer column forces a cast.
- `IS DISTINCT FROM`, `<>` on a high-selectivity column.
- `ORDER BY col LIMIT 1` where `col` has too much correlation with table
  order — the planner may prefer a Seq Scan with "abort early".
- Negative predicates (`NOT IN`, `NOT LIKE '%x%'`).

## Rule set

- Every `FOREIGN KEY` should have an index on the referring column (Postgres
  does not create it automatically).
- Every column used in `WHERE`, `JOIN`, `ORDER BY`, `GROUP BY` is a
  candidate — but only if the query shape justifies it.
- For hot composite queries, the right multi-column index often beats three
  single-column ones.
- Use `pg_stat_statements` to find the queries worth indexing for.
