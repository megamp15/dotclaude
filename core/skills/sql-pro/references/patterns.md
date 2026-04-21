# SQL patterns

Recipes for recurring problems.

## Top-N per group

```sql
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY grp ORDER BY score DESC) AS rn
    FROM items
)
SELECT * FROM ranked WHERE rn <= 3;
```

On Postgres, `DISTINCT ON` is cleaner when N=1:

```sql
SELECT DISTINCT ON (grp) *
FROM items
ORDER BY grp, score DESC;
```

## Deduplication

```sql
-- Find dups
SELECT email, COUNT(*)
FROM users
GROUP BY email
HAVING COUNT(*) > 1;

-- Keep newest, delete rest
DELETE FROM users
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
        FROM users
    ) t
    WHERE rn > 1
);
```

Prevent with a `UNIQUE` constraint after you've cleaned.

## Pagination — keyset vs. offset

**Keyset** (large tables):

```sql
SELECT id, title, created_at
FROM posts
WHERE (created_at, id) < ($last_at, $last_id)
ORDER BY created_at DESC, id DESC
LIMIT 20;
```

Why `(a, b) < (x, y)`? Row-wise comparison — avoids "equal timestamp" corner
cases.

**Offset** (simple, small tables, admin tools):

```sql
SELECT id, title
FROM posts
ORDER BY id DESC
LIMIT 20 OFFSET 200;
```

Offset becomes linear in page depth — avoid for user-facing feeds.

## Gaps and islands

"Find contiguous runs". Core trick: subtract `ROW_NUMBER()` from the
sequence to collapse runs to a constant.

```sql
-- Contiguous streaks of daily activity per user
WITH daily AS (
    SELECT DISTINCT user_id, DATE(event_at) AS day
    FROM events
),
grouped AS (
    SELECT
        user_id,
        day,
        day - (ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY day))::int AS grp
    FROM daily
)
SELECT user_id, MIN(day) AS start_day, MAX(day) AS end_day, COUNT(*) AS streak
FROM grouped
GROUP BY user_id, grp
ORDER BY streak DESC;
```

## Sessionization

See `window-functions.md` — running `SUM(is_new_session)` is the cleanest
approach.

## Pivot

**Crosstab manually** (portable):

```sql
SELECT
    user_id,
    SUM(CASE WHEN status = 'paid'      THEN 1 ELSE 0 END) AS paid,
    SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END) AS cancelled,
    SUM(CASE WHEN status = 'pending'   THEN 1 ELSE 0 END) AS pending
FROM orders
GROUP BY user_id;
```

Engine-specific: Postgres `tablefunc.crosstab`, SQL Server `PIVOT`,
Snowflake `PIVOT`.

## Unpivot

Turn wide into long:

```sql
-- Portable
SELECT user_id, 'paid' AS status, paid AS count FROM user_order_stats
UNION ALL SELECT user_id, 'cancelled', cancelled FROM user_order_stats
UNION ALL SELECT user_id, 'pending',   pending   FROM user_order_stats;

-- Postgres
SELECT user_id, v.status, v.count
FROM user_order_stats u,
     LATERAL (VALUES
         ('paid',      u.paid),
         ('cancelled', u.cancelled),
         ('pending',   u.pending)
     ) AS v(status, count);
```

## Upsert / MERGE

**ANSI `MERGE`** (Postgres 15+, most engines):

```sql
MERGE INTO users AS t
USING (VALUES ($1, $2)) AS s(email, name) ON t.email = s.email
WHEN MATCHED THEN
    UPDATE SET name = s.name, updated_at = now()
WHEN NOT MATCHED THEN
    INSERT (email, name) VALUES (s.email, s.name);
```

**Postgres `ON CONFLICT`** (works in 9.5+):

```sql
INSERT INTO users (email, name)
VALUES ($1, $2)
ON CONFLICT (email)
DO UPDATE SET name = EXCLUDED.name, updated_at = now()
RETURNING *;
```

**MySQL `ON DUPLICATE KEY UPDATE`**:

```sql
INSERT INTO users (email, name)
VALUES (?, ?)
ON DUPLICATE KEY UPDATE name = VALUES(name), updated_at = now();
```

## Running total

```sql
SELECT
    day,
    revenue,
    SUM(revenue) OVER (ORDER BY day ROWS UNBOUNDED PRECEDING) AS running_total
FROM daily;
```

Per-group:

```sql
SELECT
    user_id, day, amount,
    SUM(amount) OVER (PARTITION BY user_id ORDER BY day ROWS UNBOUNDED PRECEDING) AS running_total
FROM payments;
```

## Anti-join — "X without Y"

```sql
-- Users who have never ordered
SELECT u.*
FROM users u
WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.user_id = u.id);
```

Avoid `NOT IN` here — if `orders.user_id` can be NULL, `NOT IN` returns
nothing.

## Conditional count / sum

```sql
SELECT
    user_id,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 'paid') AS paid,           -- Postgres / standard
    SUM(CASE WHEN status = 'paid' THEN 1 ELSE 0 END) AS paid2  -- portable
FROM orders
GROUP BY user_id;
```

## Last-known-value (LOCF)

Fill NULLs with the previous non-NULL:

```sql
WITH grouped AS (
    SELECT
        *,
        SUM(CASE WHEN value IS NOT NULL THEN 1 ELSE 0 END)
            OVER (ORDER BY day) AS grp
    FROM readings
)
SELECT
    day,
    FIRST_VALUE(value) OVER (PARTITION BY grp ORDER BY day) AS value_filled
FROM grouped;
```

## Pagination "with total count" without a second query

```sql
SELECT
    id, title,
    COUNT(*) OVER () AS total_rows
FROM posts
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;
```

`COUNT(*) OVER ()` adds a full scan cost — only worth it when the alternative
is a second round trip.

## Batch / bulk patterns

**Delete in chunks** (avoid long locks):

```sql
DELETE FROM events
WHERE id IN (
    SELECT id FROM events
    WHERE created_at < now() - INTERVAL '1 year'
    LIMIT 5000
);
-- loop until zero rows affected
```

**Insert from another table** (set-based):

```sql
INSERT INTO orders_archive
SELECT * FROM orders
WHERE status = 'cancelled' AND created_at < now() - INTERVAL '1 year';
```

## Soft delete vs. hard delete

Soft delete pattern:

```sql
ALTER TABLE users ADD COLUMN deleted_at timestamptz;

CREATE INDEX users_active_idx ON users (email) WHERE deleted_at IS NULL;

-- All queries add:
WHERE deleted_at IS NULL
```

Use views or row-level security to enforce the filter. Soft delete is
cheap to implement but accumulates "dead" rows — for anything you
genuinely delete a lot of, use hard delete + an `archive` table.
