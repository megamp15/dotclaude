# PostgreSQL schema design

## Types that matter

### Primary keys

```sql
-- Integer, auto-increment (preferred for most apps)
CREATE TABLE users (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ...
);

-- UUIDv4 if you need globally unique, client-generable IDs
CREATE TABLE events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),    -- pgcrypto
    ...
);

-- UUIDv7 (time-ordered, 15+) — best of both worlds, but check support
```

Avoid `serial` / `bigserial` in new tables — use `GENERATED ALWAYS AS IDENTITY`.
Same semantics, cleaner ownership of the sequence, easier migrations.

### Text

- **`text`** is the default. `varchar(n)` adds a CHECK, no storage savings.
- **`char(n)`** pads with spaces. Don't use it. Ever.
- **`citext`** for case-insensitive (emails, usernames). Costs a small extension.

### Numbers

- **Integers**: `smallint` (2B), `integer` (4B), `bigint` (8B). Default to
  `bigint` for IDs; `integer` for counts.
- **Money / exact decimals**: `numeric(precision, scale)`. Never `float4` /
  `float8` — floats lose precision at arbitrary decimal places.
- **Floats** are fine for scientific / analytical workloads where precision
  loss is expected.

### Timestamps

Always `timestamptz` (`timestamp with time zone`). Stored as UTC, converted to
session timezone on output. `timestamp` (without tz) is a ticking time bomb —
the moment a second client connects from another zone, your data is ambiguous.

```sql
CREATE TABLE events (
    occurred_at timestamptz NOT NULL DEFAULT now(),
    ...
);
```

Date-only: `date`. Time-only: `time`. Intervals: `interval`.

### Boolean

`boolean`, not `int 0/1`. `WHERE active` reads naturally and type-checks.

### JSON vs JSONB

- **`jsonb`** — indexed, binary, deduplicated keys, fast queries. Always prefer.
- **`json`** — preserves source (whitespace, key order, duplicate keys). Only
  use if you're literally caching the original response and will never query
  into it.

### Arrays

Postgres has real array types:

```sql
CREATE TABLE posts (
    id bigint PRIMARY KEY,
    tags text[] NOT NULL DEFAULT '{}'
);

SELECT * FROM posts WHERE 'typescript' = ANY(tags);
CREATE INDEX posts_tags_idx ON posts USING gin (tags);
```

Good for small, bounded sets (tags, flags). Bad for anything you'll *join* to.
If you find yourself unnesting frequently, model it as a side table.

### Enums

Two options:

```sql
-- ENUM type — compact, fast, hard to alter
CREATE TYPE order_status AS ENUM ('pending', 'paid', 'shipped');
CREATE TABLE orders (status order_status NOT NULL DEFAULT 'pending');

-- CHECK constraint — flexible, easy to evolve
CREATE TABLE orders (
    status text NOT NULL CHECK (status IN ('pending', 'paid', 'shipped'))
        DEFAULT 'pending'
);
```

Rule of thumb: `CHECK` when the list is volatile; `ENUM` when it's stable and
you need the byte savings / sortable ordinal.

Adding an `ENUM` value is cheap (`ALTER TYPE … ADD VALUE`), removing one is
not (requires rename + recreate + data migration).

### Composite types

Built-in structured values:

```sql
CREATE TYPE address AS (
    street text,
    city text,
    postal text
);

CREATE TABLE customers (
    id bigint PRIMARY KEY,
    billing_address address,
    shipping_address address
);
```

Use sparingly — most teams end up with side tables for anything non-trivial.
But for value objects (money with currency, lat/lng, etc.), composites keep
the schema clean.

## Constraints earn their keep

```sql
CREATE TABLE subscriptions (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    plan text NOT NULL CHECK (plan IN ('free', 'pro', 'enterprise')),
    started_at timestamptz NOT NULL,
    ended_at timestamptz,
    CHECK (ended_at IS NULL OR ended_at > started_at),
    UNIQUE (user_id, started_at)
);
```

Rules:

- `NOT NULL` is the default mindset; make every field prove it needs to allow
  `NULL`.
- `CHECK` enforces invariants the app can't (date range ordering, sum = 100).
- `UNIQUE` with a `WHERE` (partial unique) is how you do "one active row per
  user": `CREATE UNIQUE INDEX ON subs (user_id) WHERE ended_at IS NULL`.
- `FOREIGN KEY` — yes, in production. The perf cost is usually tiny and the
  integrity win is huge. Add them.

## Generated columns

Derived, always-in-sync columns for the DB to maintain:

```sql
ALTER TABLE articles ADD COLUMN
    search_vector tsvector
    GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || body)) STORED;

CREATE INDEX articles_search_idx ON articles USING gin (search_vector);
```

Good for FTS vectors, normalized lowercase emails, computed flags. `STORED`
only — Postgres doesn't support `VIRTUAL` generated columns yet.

## JSONB for variation, not avoidance

Use `jsonb` when the set of fields legitimately varies (per-event payloads,
feature flags, user preferences). Don't use it to avoid modeling:

```sql
-- ❌ bad — every query does jsonb_path
CREATE TABLE users_bad (
    id bigint PRIMARY KEY,
    data jsonb    -- "just put everything in here"
);

-- ✅ good — common fields are columns, variable payload is jsonb
CREATE TABLE events (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id bigint NOT NULL REFERENCES users(id),
    kind text NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now(),
    payload jsonb NOT NULL     -- shape varies per event kind
);
CREATE INDEX events_payload_gin ON events USING gin (payload jsonb_path_ops);
```

Key predicates:

```sql
WHERE payload @> '{"status": "paid"}'       -- contains
WHERE payload -> 'order' ->> 'id' = '123'   -- extract text
WHERE jsonb_path_exists(payload, '$.items[*] ? (@.qty > 0)')
```

## Tables that grow forever

Rules of thumb — if any of these will eventually hit the table, design for
them now:

- **Billions of rows**: partition (see `ops.md`).
- **Time-series**: consider BRIN indexes and monthly / weekly partitions.
- **Soft delete**: `deleted_at timestamptz` + partial index + include
  `WHERE deleted_at IS NULL` in queries. Or move to an `archived_` table.
- **Audit log**: append-only, BRIN on `created_at`, no updates.

## Naming conventions

- Tables: plural, snake_case (`users`, `order_items`).
- Columns: snake_case, no type prefixes (`email`, not `str_email`).
- Primary key: `id`.
- Foreign key: `<referent>_id` (`user_id`, `order_id`).
- Timestamps: `created_at`, `updated_at`, `deleted_at`.
- Indexes: `<table>_<col(s)>_idx` (`users_email_idx`).
- Constraints: `<table>_<col>_check` / `<table>_<col>_key`.
- Sequences: managed by `GENERATED AS IDENTITY`; don't name them yourself.

Be ruthlessly consistent. Naming drift makes every query a lookup.
