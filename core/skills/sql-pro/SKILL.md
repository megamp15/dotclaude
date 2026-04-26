---
name: sql-pro
description: Engine-agnostic SQL craft — set-based thinking, joins, window functions, CTEs (recursive and otherwise), aggregates, pivots, dedup, gaps-and-islands, NULL semantics, and portable style. Distinct from `postgres-pro` (engine-specific) and `architect` rest-api mode (contracts, not queries).
source: core
triggers: /sql-pro, SQL query, window function, CTE, WITH RECURSIVE, LATERAL JOIN, gaps and islands, NULL semantics, pivot / unpivot, correlated subquery, ROWS BETWEEN, rank vs row_number, SQL performance
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/sql-pro
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# sql-pro

Deep, engine-agnostic SQL expertise — the parts of the language that every
serious backend person eventually needs, no matter whether the engine is
Postgres, MySQL, SQL Server, or Snowflake.

> **See also:**
>
> - `core/skills/postgres-pro/` — PostgreSQL-specific expertise (EXPLAIN,
>   JSONB, locking, partitioning)
> - `core/rules/database.md` — cross-project DB conventions
> - `stacks/fastapi/skills/fastapi-expert/references/async-sqlalchemy.md` —
>   SQLAlchemy query patterns
> - `core/skills/architect/` — when the question is really
>   "should this be a query or an app computation"

## When to use this skill

- Replacing a procedural loop with a set-based query.
- Writing a non-trivial join / window / CTE that you want to get right the
  first time.
- Reading someone else's SQL and figuring out what it *actually* does.
- Porting between engines and hitting dialect differences.
- Tuning a query where the shape — not the indexes — is the problem.

## References (load on demand)

- [`references/set-thinking.md`](references/set-thinking.md) — the shift from
  row-by-row to set-based thinking; joins (INNER, LEFT, RIGHT, FULL, CROSS,
  LATERAL), semi-/anti-joins, aggregation patterns, NULL rules.
- [`references/window-functions.md`](references/window-functions.md) — `OVER`
  clause, `PARTITION BY`, frame (`ROWS` / `RANGE` / `GROUPS`), the ranking
  family (`ROW_NUMBER`, `RANK`, `DENSE_RANK`, `NTILE`), navigation
  (`LEAD`/`LAG`/`FIRST_VALUE`/`LAST_VALUE`), and running aggregates.
- [`references/ctes.md`](references/ctes.md) — `WITH` mechanics, recursive
  CTEs (graphs, trees, running totals), materialization, when CTEs help vs.
  hurt.
- [`references/patterns.md`](references/patterns.md) — top-N per group,
  dedup, gaps-and-islands, pivot / unpivot, anti-join vs. `NOT IN`, running
  totals, moving averages, MERGE/UPSERT.

## Core workflow

1. **Describe the shape in English first.** "For each customer, the most
   recent order with total ≥ 100." If you can't say it, you can't write it.
2. **Think in sets.** Filter, join, group — not loop.
3. **Pick the right tool.**
   - Row-by-row rank / running total → window function.
   - Self-referencing hierarchy / graph → recursive CTE.
   - "One row per group, best by some metric" → `DISTINCT ON` (Postgres) or
     `ROW_NUMBER() OVER (PARTITION BY …)`.
4. **Respect NULL.** `NULL = NULL` is not `TRUE`. Use `IS DISTINCT FROM`,
   `COALESCE`, and be explicit.
5. **Let EXPLAIN decide.** Never "optimize" a query by reading it. Plan first.

## Defaults

| Task | Default |
|---|---|
| "One row per group, latest by X" | `ROW_NUMBER() OVER (PARTITION BY grp ORDER BY X DESC)` + filter `= 1` |
| Hierarchical traversal | recursive CTE with `UNION ALL` + cycle guard |
| Pagination (large table) | keyset `WHERE id > $last ORDER BY id LIMIT N` |
| "Number of distinct values per group" | `COUNT(DISTINCT col)` with caveats; approximate → engine-specific (`APPROX_COUNT_DISTINCT`) |
| Portable "upsert" | `MERGE INTO … WHEN MATCHED … WHEN NOT MATCHED …` (ANSI; Postgres 15+, most major engines) |
| Dedup keeping newest | `ROW_NUMBER() … ORDER BY created_at DESC` → filter `= 1` in outer query |
| Percentile | `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY col)` |
| Running total | `SUM(x) OVER (ORDER BY t ROWS UNBOUNDED PRECEDING)` |
| Moving 7-day average | `AVG(x) OVER (ORDER BY day ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)` |
| Exists check | `EXISTS (SELECT 1 FROM …)`, not `COUNT(*) > 0` |

## Anti-patterns

- **`SELECT *`** in application code. You pay for columns you don't use and
  break on schema change.
- **`COUNT(*) > 0`** to test existence — `EXISTS` short-circuits, `COUNT`
  scans.
- **`NOT IN (subquery)`** with nullable values — returns no rows if *any*
  subquery row is NULL. Use `NOT EXISTS`.
- **`DISTINCT` as a crutch** to paper over a bad join that duplicates rows.
- **`OR` in `WHERE` on two different columns** — often defeats indexes; use
  `UNION ALL` of two predicates.
- **`ORDER BY` without a stable tiebreaker.**
- **Correlated subquery in `SELECT`** that should be a join or window
  function — often 10–100× slower.
- **Business logic in triggers.** Invisible, untested, often recursive.
- **String-concatenating user input into SQL.** Always parameterize.

## Dialect differences that trip people up

| Feature | Postgres | MySQL | SQL Server | Snowflake / BigQuery |
|---|---|---|---|---|
| String concat | `\|\|` or `concat()` | `concat()` | `+` or `concat()` | `\|\|` / `concat` |
| Limit | `LIMIT n OFFSET m` | `LIMIT m, n` | `OFFSET … ROWS FETCH NEXT … ROWS ONLY` | `LIMIT n OFFSET m` |
| Top-N distinct | `DISTINCT ON (grp)` | window fn | window fn | window fn |
| Upsert | `ON CONFLICT … DO UPDATE` or `MERGE` (15+) | `ON DUPLICATE KEY UPDATE` | `MERGE` | `MERGE` |
| Current timestamp | `now()` or `current_timestamp` | `now()` | `GETDATE()` / `SYSDATETIME()` | `current_timestamp()` |
| Identity | `GENERATED ALWAYS AS IDENTITY` | `AUTO_INCREMENT` | `IDENTITY(1,1)` | `AUTOINCREMENT` |
| JSON | `jsonb`, `->`, `->>` | `JSON`, `JSON_EXTRACT`, `->>` | `FOR JSON`, `OPENJSON` | `VARIANT`, `:`, `object_*` |
| Case-insensitive | `ILIKE` or `citext` | default collation | default collation | `ILIKE` |
| `LIMIT` inside subquery vs. CTE | fine | fine | CTE only (`TOP n` allowed) | fine |

When writing portable SQL: stick to ANSI (`||`, `CASE`, standard `JOIN`,
standard aggregates, windows), avoid vendor JSON operators in shared code,
wrap engine-specific bits behind a thin data-access layer.

## Output format

For query-design questions:

```
English description:
  <the query in one paragraph>

Query:
  <the SQL>

Why this shape:
  <why a window / CTE / lateral / etc.>

NULL behavior:
  <explicit note — what happens if inputs are NULL>

Perf notes:
  <index(es) this depends on; expected plan>
```

For troubleshooting:

```
What this query actually does:
  <line-by-line trace, not "what the author meant">

Gotcha:
  <the specific semantic quirk>

Rewrite:
  <a cleaner equivalent>
```
