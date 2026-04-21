# Set-based thinking

SQL is a language for describing *sets of rows*, not for iterating. The
biggest single improvement for most developers' SQL is to stop thinking in
loops.

## Joins

### `INNER JOIN`

Rows where both sides match:

```sql
SELECT u.id, u.email, o.total
FROM users u
INNER JOIN orders o ON o.user_id = u.id
WHERE o.status = 'paid';
```

### `LEFT JOIN`

All rows from the left, matching (or NULL) from the right:

```sql
SELECT u.id, u.email, COUNT(o.id) AS order_count
FROM users u
LEFT JOIN orders o ON o.user_id = u.id
GROUP BY u.id, u.email;
```

`LEFT JOIN … WHERE o.status = 'paid'` is a common bug — the `WHERE`
converts it back to an inner join. Filter in the `ON`:

```sql
LEFT JOIN orders o ON o.user_id = u.id AND o.status = 'paid'
```

### `RIGHT JOIN` / `FULL OUTER JOIN`

`RIGHT JOIN` exists but always rewritable as `LEFT JOIN` by swapping sides.
Stick to `LEFT`.

`FULL OUTER JOIN` — all rows from both sides, NULL where no match. Useful
for diffing two snapshots.

### `CROSS JOIN`

Cartesian product. Useful for "expand every row against a calendar" or
generating combinations:

```sql
SELECT d.day, u.id
FROM generate_series('2026-01-01'::date, '2026-01-31', '1 day') d(day)
CROSS JOIN users u;
```

### `LATERAL JOIN`

A per-row subquery. The right side can reference columns from the left.
Perfect for "for each user, give me the 3 most recent orders":

```sql
SELECT u.id, o.*
FROM users u
LEFT JOIN LATERAL (
    SELECT id, total, created_at
    FROM orders
    WHERE user_id = u.id
    ORDER BY created_at DESC
    LIMIT 3
) o ON TRUE;
```

Works on Postgres, SQL Server (`CROSS APPLY`/`OUTER APPLY`), Snowflake. No
MySQL < 8.0.14.

### Semi-joins and anti-joins

`EXISTS` = semi-join: "rows where at least one match exists". Can be
faster than `IN` with a large subquery because it short-circuits.

```sql
SELECT u.*
FROM users u
WHERE EXISTS (
    SELECT 1 FROM orders o
    WHERE o.user_id = u.id AND o.status = 'paid'
);
```

`NOT EXISTS` = anti-join: "rows with no matching entry".

```sql
SELECT u.*
FROM users u
WHERE NOT EXISTS (
    SELECT 1 FROM orders o WHERE o.user_id = u.id
);
```

**Prefer `NOT EXISTS` over `NOT IN`** — `NOT IN` with a NULL-containing
subquery returns empty due to NULL semantics. Classic silent bug.

## NULL semantics

- `NULL = NULL` is `NULL`, not `TRUE`.
- `NULL <> x` is `NULL`, not `TRUE`.
- `NULL + anything` is `NULL`.
- Most aggregates **skip NULLs** (`SUM`, `AVG`, `COUNT(col)`), except
  `COUNT(*)`.
- `ORDER BY` sorts NULL last by default in SQL Server / Postgres;
  `NULLS FIRST`/`NULLS LAST` is explicit.

Write NULL-safe comparisons:

```sql
-- "x is different from y, treating NULL as a distinct value"
WHERE a IS DISTINCT FROM b         -- Postgres / standard
WHERE NOT (a <=> b)                -- MySQL null-safe equal
WHERE (a <> b OR (a IS NULL) <> (b IS NULL))   -- ANSI
```

Defaulting NULL to a sentinel:

```sql
SELECT COALESCE(middle_name, '') AS middle_name FROM users;
```

## Aggregation

```sql
SELECT
    user_id,
    COUNT(*) AS orders,
    SUM(total) AS revenue,
    AVG(total) AS avg_order,
    MAX(created_at) AS last_order_at
FROM orders
WHERE status = 'paid'
GROUP BY user_id
HAVING COUNT(*) >= 2
ORDER BY revenue DESC;
```

Rules:

- Every column in `SELECT` is either in `GROUP BY` or inside an aggregate.
- `HAVING` filters *after* aggregation; `WHERE` filters before.
- `COUNT(*)` counts rows; `COUNT(col)` skips NULLs; `COUNT(DISTINCT col)`
  is well-defined but can be expensive.

### `FILTER`

Conditional aggregation is often clearer than `CASE` inside the aggregate:

```sql
SELECT
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE status = 'paid') AS paid,
    SUM(total) FILTER (WHERE status = 'paid') AS paid_revenue
FROM orders;
```

Postgres / standard. For engines without `FILTER`, use
`SUM(CASE WHEN … THEN … ELSE 0 END)`.

### Grouping sets, `ROLLUP`, `CUBE`

Multiple aggregation levels in one pass:

```sql
SELECT region, product, SUM(revenue)
FROM sales
GROUP BY ROLLUP (region, product);
-- emits: (region,product), (region), ()
```

Use for pivot-style reports that need subtotals.

## Subqueries: scalar, row, table

```sql
-- Scalar (one row, one column)
SELECT *, (SELECT COUNT(*) FROM orders o WHERE o.user_id = u.id) AS cnt
FROM users u;

-- Row
SELECT * FROM users WHERE (city, country) = (SELECT city, country FROM users WHERE id = 1);

-- Table
SELECT * FROM (SELECT id, email FROM users) t;
```

Correlated scalar subqueries can be slow — rewrite as join + aggregate if
the subquery hits more than a few rows.

## Deduplication

Keeping one row per group:

```sql
-- Postgres
SELECT DISTINCT ON (email) *
FROM users
ORDER BY email, created_at DESC;

-- Portable: window function + outer filter
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY email ORDER BY created_at DESC) AS rn
    FROM users
)
SELECT * FROM ranked WHERE rn = 1;
```

## Useful scalar functions

- **`COALESCE(a, b, c)`** — first non-NULL.
- **`NULLIF(a, b)`** — NULL if `a = b`, else `a`. Great for turning empty
  strings into NULL.
- **`GREATEST(a, b, c)` / `LEAST(…)`** — row-level max/min across columns.
- **`CASE WHEN … THEN … END`** — the portable conditional. Use this, not
  engine-specific `IIF` / `DECODE`.

## Performance rules of thumb

- Narrow early (`WHERE` before `JOIN` where possible — the planner usually
  does this, but readable SQL helps).
- Join on indexed columns.
- Avoid functions on indexed columns in `WHERE` (`WHERE lower(email) = …`
  defeats an index on `email`).
- Prefer `EXISTS` to `COUNT(*) > 0`.
- Avoid `SELECT DISTINCT` if you can achieve deduplication by joining
  differently.
- When in doubt, `EXPLAIN`.

## Style

- Keywords UPPERCASE or lowercase — pick one and stick to it project-wide.
- One clause per line for non-trivial queries.
- Indent subqueries / CTEs two spaces.
- Columns on separate lines when > 3 or joining multiple tables.
- Prefer column names to `*` in anything committed.
- Qualify every column with its table alias in multi-table queries.
