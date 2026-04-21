# Window functions

The thing that separates "can write SQL" from "thinks in SQL".

## Mental model

A window function computes over a *window* of rows associated with each
output row, without collapsing the rows (unlike `GROUP BY`).

```sql
SELECT
    user_id,
    order_id,
    total,
    SUM(total) OVER (PARTITION BY user_id) AS user_total
FROM orders;
```

Each row is returned; `user_total` is the sum of all orders for that
user_id.

## Anatomy of `OVER`

```sql
func(args) OVER (
    PARTITION BY col_a, col_b        -- group into windows (optional)
    ORDER BY col_c [DESC] [NULLS LAST]  -- ordering inside window (optional)
    ROWS BETWEEN ... AND ...          -- frame (optional)
)
```

- **`PARTITION BY`** — independent windows per partition. Without it, the
  window is the whole result set.
- **`ORDER BY`** — determines row ordering for navigation / ranking /
  cumulative aggregates.
- **Frame** — `ROWS` (physical rows), `RANGE` (value-based), or `GROUPS`
  (peer groups). Defaults to `RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`
  when `ORDER BY` is present, else the whole partition.

## Ranking family

```sql
SELECT
    user_id,
    total,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY total DESC) AS rn,
    RANK()       OVER (PARTITION BY user_id ORDER BY total DESC) AS rk,
    DENSE_RANK() OVER (PARTITION BY user_id ORDER BY total DESC) AS drk,
    NTILE(4)     OVER (ORDER BY total)                           AS quartile
FROM orders;
```

| Function | Ties | Gaps |
|---|---|---|
| `ROW_NUMBER` | Arbitrary tiebreaker | No gaps: 1,2,3,4 |
| `RANK` | Same rank | Gaps: 1,2,2,4 |
| `DENSE_RANK` | Same rank | No gaps: 1,2,2,3 |
| `NTILE(N)` | Assigns to N buckets | No gaps |

**Pick one**:

- Reporting ("top 3 per category") — `ROW_NUMBER` (deterministic with a tie-
  breaker in `ORDER BY`).
- Competition rankings (ties matter) — `RANK` or `DENSE_RANK`.
- Bucket into quartiles / deciles — `NTILE`.

## Navigation

```sql
SELECT
    user_id,
    order_id,
    created_at,
    LAG(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS prev_order_at,
    LEAD(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS next_order_at,
    FIRST_VALUE(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS first_order_at,
    LAST_VALUE(created_at)  OVER (
        PARTITION BY user_id
        ORDER BY created_at
        ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS last_order_at
FROM orders;
```

Note: `LAST_VALUE` without an explicit frame gives the current row, not
the last — because the default frame ends at the current row. This is
one of the most common SQL gotchas.

`LAG(col, 3, 0)` — 3 rows back, with 0 as default when out of range.

## Cumulative / running aggregates

Running total:

```sql
SELECT
    day,
    revenue,
    SUM(revenue) OVER (ORDER BY day ROWS UNBOUNDED PRECEDING) AS running_total
FROM daily;
```

Moving 7-day window:

```sql
SELECT
    day,
    AVG(revenue) OVER (
        ORDER BY day
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) AS moving_7d_avg
FROM daily;
```

Cumulative % of total:

```sql
SELECT
    day,
    revenue,
    revenue * 100.0 / SUM(revenue) OVER () AS pct_of_total
FROM daily;
```

## `ROWS` vs. `RANGE` vs. `GROUPS`

- **`ROWS`** — count physical rows before/after.
- **`RANGE`** — based on the value of the `ORDER BY` column. With `BETWEEN
  INTERVAL '7 days' PRECEDING AND CURRENT ROW`, includes every row within
  7 days of the current — gaps in data change what's in the frame.
- **`GROUPS`** — peer groups (rows with the same `ORDER BY` value).

For "last 7 days" in a daily series where *every* day exists: `ROWS 6
PRECEDING` is fine. If days can be missing: use `RANGE BETWEEN INTERVAL
'7 days' PRECEDING AND CURRENT ROW` (Postgres / standard).

## Percentiles

```sql
SELECT
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_ms) AS median,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms) AS p95,
    PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY duration_ms) AS p99
FROM requests;
```

`PERCENTILE_CONT` interpolates; `PERCENTILE_DISC` picks the closest
actual value. Ordered-set aggregates, standard SQL.

## Common patterns

### Top-N per group

```sql
WITH ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (PARTITION BY category ORDER BY score DESC, id) AS rn
    FROM items
)
SELECT * FROM ranked WHERE rn <= 3;
```

### First, last, most recent

```sql
-- Latest status per user (single pass)
SELECT DISTINCT ON (user_id)
    user_id, status, created_at
FROM events
ORDER BY user_id, created_at DESC;          -- Postgres

-- Portable
SELECT user_id, status, created_at FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC) AS rn
    FROM events
) t WHERE rn = 1;
```

### Gap detection

Find users with a gap > 30 days between orders:

```sql
WITH withlag AS (
    SELECT
        user_id,
        created_at,
        LAG(created_at) OVER (PARTITION BY user_id ORDER BY created_at) AS prev_at
    FROM orders
)
SELECT user_id, created_at, created_at - prev_at AS gap
FROM withlag
WHERE prev_at IS NOT NULL
  AND created_at - prev_at > INTERVAL '30 days';
```

### Sessionization

Group events into sessions with a 30-minute idle gap:

```sql
WITH gaps AS (
    SELECT
        user_id, event_at,
        CASE
            WHEN event_at - LAG(event_at) OVER (PARTITION BY user_id ORDER BY event_at)
                 > INTERVAL '30 min'
              OR LAG(event_at) OVER (PARTITION BY user_id ORDER BY event_at) IS NULL
            THEN 1 ELSE 0
        END AS is_new_session
    FROM events
),
sessions AS (
    SELECT
        *,
        SUM(is_new_session) OVER (PARTITION BY user_id ORDER BY event_at) AS session_id
    FROM gaps
)
SELECT user_id, session_id, MIN(event_at), MAX(event_at), COUNT(*) AS events
FROM sessions
GROUP BY user_id, session_id;
```

This is the canonical "islands" problem — spotting contiguous ranges.

### Deduplication

```sql
DELETE FROM users
WHERE id IN (
    SELECT id FROM (
        SELECT id, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at) AS rn
        FROM users
    ) t WHERE rn > 1
);
```

### Running distinct count (approx)

Exact `COUNT(DISTINCT)` has no window equivalent. Use a subquery:

```sql
SELECT
    day,
    (
      SELECT COUNT(DISTINCT user_id)
      FROM events e2
      WHERE e2.day <= e1.day
    ) AS cumulative_users
FROM events e1
GROUP BY day;
```

Or reach for engine-specific sketches (Postgres `hll`, BigQuery
`APPROX_COUNT_DISTINCT`).

## Performance notes

- Window functions process after `WHERE` / `GROUP BY`, before `ORDER BY` /
  `LIMIT`. Filter aggressively before.
- Each distinct `OVER` clause typically requires its own sort / partition
  step. Reuse identical windows with `WINDOW w AS (…)` syntax where the
  engine supports it.
- For massive tables, consider whether the window computation should
  actually run in a materialized view or nightly job.
