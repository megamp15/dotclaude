---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/api-designer/references/pagination.md
ported-at: 2026-04-17
adapted: true
---

# Pagination

Never return an unbounded list. Pick a strategy before you ship.

## Strategy comparison

| Feature | Offset | Page | Cursor | Keyset |
|---|---|---|---|---|
| Performance at large N | Poor | Poor | Excellent | Excellent |
| Random access | Yes | Yes | No | No |
| Total count | Easy (but slow) | Easy | Usually no | Optional |
| Consistency during writes | Poor | Poor | Excellent | Excellent |
| Complexity | Simple | Simple | Medium | Medium |
| Typical use | Small, static sets | Legacy web UIs | Feeds, streams, large sets | Large sets with simple order |

**Default: cursor.** Fall back to offset/page only for small, slow-changing
data where random access is a genuine requirement.

## Cursor-based (default)

```http
GET /orders?limit=50
GET /orders?limit=50&cursor=eyJpZCI6Im9yZF8wMUhCIn0
```

```json
{
  "data": [ ... 50 items ... ],
  "pagination": {
    "limit": 50,
    "has_more": true,
    "next_cursor": "eyJpZCI6Im9yZF8wMUhDIn0",
    "prev_cursor": "eyJpZCI6Im9yZF8wMUhBIn0"
  }
}
```

**Cursor is opaque** — base64-encoded JSON with the last-seen sort key(s):

```
{ "id": "ord_01HC", "created_at": "2026-04-17T12:00:00Z" }
```

**SQL pattern:**

```sql
-- First page
SELECT *
FROM orders
ORDER BY created_at DESC, id DESC
LIMIT 50;

-- Next page (cursor = last row's (created_at, id))
SELECT *
FROM orders
WHERE (created_at, id) < ($cursor_ts, $cursor_id)
ORDER BY created_at DESC, id DESC
LIMIT 50;
```

**Pros:** consistent under concurrent writes, O(log n) with proper index,
no COUNT query.

**Cons:** no "jump to page 5", no `total`, cursor format needs versioning
if sort changes.

## Offset / page-based

```http
GET /orders?limit=20&offset=40
GET /orders?page=3&per_page=20
```

```json
{
  "data": [ ... ],
  "pagination": {
    "page": 3,
    "per_page": 20,
    "total": 1523,
    "total_pages": 77,
    "has_more": true
  }
}
```

**Good for:** small admin tables, static catalogs, reports where COUNT is cheap.

**Bad for:** large datasets (offset scans degrade linearly), real-time data
(items shift between pages during paging).

## Keyset pagination

Transparent cursor — uses an actual field value:

```http
GET /orders?after_id=ord_01HBX&limit=50
GET /events?after_created_at=2026-04-17T10:00:00Z&limit=100
```

```sql
SELECT * FROM orders
WHERE id > 'ord_01HBX'
ORDER BY id ASC
LIMIT 50;
```

Like cursor-based, but the cursor is visible. Good when clients might want
to reason about the cursor (e.g., time-based windows).

## Limits

Always enforce:

```json
{
  "default_limit": 25,
  "max_limit": 100,
  "min_limit": 1
}
```

```http
GET /orders?limit=9999
→ 422 Unprocessable Entity
{
  "code": "INVALID_LIMIT",
  "detail": "limit must be between 1 and 100"
}
```

Never return more than `max_limit`. Silently capping is acceptable for
forgiving UX; clear errors are better for API hygiene.

## Total counts — usually omit

Including `total`:
- Requires a `COUNT(*)` query.
- Is expensive at scale.
- Is stale immediately in high-write systems.

Default to `has_more: true/false` — it's what UIs need for "next"/"load more".

Offer total via opt-in when the cost is worth it:

```http
GET /orders?limit=50&include_total=true
```

## Sorting with pagination

```http
GET /orders?sort=-created_at,id&limit=50
```

For cursor pagination, the cursor **must include all sort fields**. Otherwise
ties on the primary sort produce duplicates/skips:

```json
{
  "cursor": {
    "created_at": "2026-04-17T12:00:00Z",
    "id": "ord_01HBX..."
  }
}
```

## Filtering with pagination

Apply filters **before** pagination. Each filtered pagination is a different
cursor space; don't mix cursors across different filter combinations.

```http
GET /orders?status=open&limit=50
GET /orders?status=open&limit=50&cursor=...  # cursor scoped to this filter
```

If the filter changes, drop the cursor client-side.

## Response format — pick one, stick to it

### Inline pagination object (recommended)

```json
{
  "data": [ ... ],
  "pagination": {
    "limit": 50,
    "has_more": true,
    "next_cursor": "...",
    "prev_cursor": "..."
  }
}
```

### Link header (RFC 5988) — used by GitHub

```http
Link: <https://api.example.com/orders?cursor=xyz&limit=50>; rel="next",
      <https://api.example.com/orders?cursor=abc&limit=50>; rel="prev"
```

Pick one and use it consistently across every paginated endpoint.

## Edge cases

- **Empty result:** `data: []`, `has_more: false`, `next_cursor: null`. 200, not 404.
- **Out-of-range offset:** 200 with empty data, or 422 — decide and document.
- **Stale cursor (item it referenced is deleted):** cursor still valid; server
  seeks past it. Consumer must not care.
- **Cursor from a different sort/filter:** 422 `INVALID_CURSOR`.

## Checklist

- [ ] Strategy chosen and documented
- [ ] `default_limit` and `max_limit` enforced
- [ ] `has_more` always present
- [ ] Cursor is opaque + versioned in its own encoding
- [ ] Sort stable across pages (secondary sort on unique column)
- [ ] Filter + pagination interaction documented
- [ ] Edge cases (empty, OOR, bad cursor) tested
