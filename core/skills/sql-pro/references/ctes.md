# CTEs and recursion

## Non-recursive CTEs

```sql
WITH recent_orders AS (
    SELECT user_id, MAX(created_at) AS last_order
    FROM orders
    WHERE status = 'paid'
    GROUP BY user_id
),
churned AS (
    SELECT *
    FROM recent_orders
    WHERE last_order < now() - INTERVAL '90 days'
)
SELECT u.email, c.last_order
FROM users u
JOIN churned c USING (user_id);
```

CTEs:

- Name subresults so queries read top-down.
- Reuse a subquery multiple times in the same statement.
- Keep joins flat instead of deeply nested subqueries.

### Materialization behavior

Historically Postgres always materialized CTEs (optimization fence).
Postgres 12+ inlines CTEs by default unless:

- The CTE is referenced > 1 time.
- The CTE uses `VOLATILE` functions, `FOR UPDATE`, or DML.
- You add `MATERIALIZED` / `NOT MATERIALIZED`:

```sql
WITH slow_cte AS MATERIALIZED (      -- forces materialization
    SELECT ...
)
```

MySQL 8+, SQL Server: may or may not materialize; engine decides.
Snowflake / BigQuery: CTEs are logical, the optimizer decides.

### When CTEs help vs. hurt

CTEs help when:

- A subquery is referenced twice.
- Breaking a 200-line query into layers aids comprehension.
- You want to force materialization (Postgres `AS MATERIALIZED`) to cache a
  known-expensive subresult.

CTEs hurt when:

- They accidentally prevent predicate pushdown (pre-12 Postgres).
- They introduce materialization overhead for a cheap subquery.

When in doubt, `EXPLAIN` both shapes.

## Recursive CTEs

For hierarchies, graphs, sequences:

```sql
WITH RECURSIVE org AS (
    SELECT id, manager_id, name, 0 AS depth
    FROM employees
    WHERE manager_id IS NULL               -- anchor: root(s)

    UNION ALL

    SELECT e.id, e.manager_id, e.name, o.depth + 1
    FROM employees e
    JOIN org o ON e.manager_id = o.id      -- recursion: join back
)
SELECT * FROM org ORDER BY depth, name;
```

Structure:

- **Anchor query** (`WHERE manager_id IS NULL`) — non-recursive base.
- **Recursive term** — joins the CTE name with itself.
- **`UNION ALL`** (almost always; `UNION` deduplicates but is slower).

### Cycle detection

A cyclic graph will recurse forever. Two defenses:

```sql
WITH RECURSIVE path AS (
    SELECT id, parent_id, ARRAY[id] AS visited, false AS cycle
    FROM nodes WHERE id = 1

    UNION ALL

    SELECT n.id, n.parent_id,
           visited || n.id,
           n.id = ANY(visited)
    FROM nodes n
    JOIN path p ON n.parent_id = p.id
    WHERE NOT p.cycle
)
SELECT * FROM path;
```

Postgres 14+ has `CYCLE … SET … USING …` syntax that does this for you:

```sql
WITH RECURSIVE path AS (
    SELECT id, parent_id FROM nodes WHERE id = 1
    UNION ALL
    SELECT n.id, n.parent_id FROM nodes n JOIN path p ON n.parent_id = p.id
) CYCLE id SET is_cycle USING path_array
SELECT * FROM path;
```

### Depth limits

No built-in limit. Put your own:

```sql
-- Inside the recursive term
WHERE depth < 100
```

### Classic recursive patterns

**Generating a series** (when your engine lacks `generate_series`):

```sql
WITH RECURSIVE days AS (
    SELECT DATE '2026-01-01' AS day
    UNION ALL
    SELECT day + 1 FROM days WHERE day < DATE '2026-12-31'
)
SELECT * FROM days;
```

**Tree path (root → leaf)**:

```sql
WITH RECURSIVE tree AS (
    SELECT id, parent_id, name, name::text AS path
    FROM categories WHERE parent_id IS NULL

    UNION ALL

    SELECT c.id, c.parent_id, c.name, t.path || ' / ' || c.name
    FROM categories c
    JOIN tree t ON c.parent_id = t.id
)
SELECT id, path FROM tree ORDER BY path;
```

**Find all descendants of a node**:

```sql
WITH RECURSIVE descendants AS (
    SELECT id FROM nodes WHERE id = $root_id
    UNION ALL
    SELECT n.id FROM nodes n JOIN descendants d ON n.parent_id = d.id
)
SELECT * FROM descendants;
```

**Running totals via recursion** (when window functions aren't available):

```sql
WITH RECURSIVE run AS (
    SELECT id, amount, amount AS running
    FROM payments WHERE id = (SELECT MIN(id) FROM payments)

    UNION ALL

    SELECT p.id, p.amount, r.running + p.amount
    FROM payments p
    JOIN run r ON p.id = r.id + 1
)
SELECT * FROM run;
```

(Use window functions if available — recursion is slower and more
fragile.)

## DML inside CTEs (Postgres)

Postgres supports writes in CTEs:

```sql
WITH archived AS (
    DELETE FROM orders
    WHERE status = 'cancelled' AND created_at < now() - INTERVAL '1 year'
    RETURNING *
)
INSERT INTO orders_archive SELECT * FROM archived;
```

Every branch reads the *same snapshot*. The insert sees the pre-delete
version in the CTE output but the `orders` table is affected atomically.

Be careful: two DML CTEs operating on the same table have surprising
visibility semantics. Keep them simple.

## Readability conventions

- Name CTEs as nouns describing the set (`recent_orders`, `churned_users`,
  `monthly_totals`), not actions.
- One CTE per transformation. Don't try to be clever with 200-line
  monoliths.
- Put a comment above non-obvious CTEs explaining intent.

## Performance reminders

- Every CTE is (potentially) a materialization point. For a 1M-row
  intermediate, that's real memory.
- If an index would normally kick in but doesn't after CTE introduction,
  that's a materialization fence — inline the CTE, or use
  `NOT MATERIALIZED` (Postgres 12+).
- Recursive CTEs don't parallelize well. For gigantic graphs consider a
  dedicated graph DB or iterative app code.
