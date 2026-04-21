---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/api-designer/references/rest-patterns.md
ported-at: 2026-04-17
adapted: true
---

# REST patterns

Beyond methods and status codes — resource modeling, HATEOAS, caching,
content negotiation, and the shape of good URIs.

## Good and bad URIs

```
# Good
GET    /orders
GET    /orders/{id}
GET    /orders/{id}/line-items
POST   /orders
PATCH  /orders/{id}
DELETE /orders/{id}

# Bad
POST   /createOrder
GET    /order?action=delete
POST   /orders/{id}/actions/cancel     # use /cancellations instead
GET    /getUserById/{id}
```

**Rules:**
- Collections are plural: `/orders` not `/order`.
- Identifiers, not search params, in the path.
- Lowercase. Kebab-case for multi-word segments.
- Max 2–3 levels of nesting.
- Query params for filter, sort, field selection, search.

## Safe and idempotent methods

| Method | Safe (no side effects) | Idempotent |
|---|---|---|
| GET | ✓ | ✓ |
| HEAD | ✓ | ✓ |
| OPTIONS | ✓ | ✓ |
| POST | — | — |
| PUT | — | ✓ |
| PATCH | — | — (but often idempotent by convention) |
| DELETE | — | ✓ |

Respect semantics. `GET` must not mutate. `PUT` must be fully idempotent.

## HATEOAS (hypermedia)

Optional but pleasant for discovery:

```json
{
  "id": "ord_01HBX...",
  "status": "pending",
  "_links": {
    "self":    { "href": "/orders/ord_01HBX..." },
    "cancel":  { "href": "/orders/ord_01HBX.../cancellation", "method": "POST" },
    "items":   { "href": "/orders/ord_01HBX.../line-items" }
  }
}
```

Don't enforce HATEOAS on internal APIs if it adds ceremony without value.
Do consider it for public long-lived APIs.

## Content negotiation

```http
Accept: application/json
Accept-Language: en-US
Accept-Encoding: gzip, br

Content-Type: application/json; charset=utf-8
Content-Language: en-US
```

For errors, always `application/problem+json` (RFC 7807).

## Caching

```http
Cache-Control: public, max-age=3600           # 1h public cache
Cache-Control: private, no-cache              # client-only, revalidate
Cache-Control: no-store                       # sensitive, never cache

ETag: "33a64df551425fcc55e4d42a148795d9f25f89d4"
Last-Modified: Wed, 15 Jan 2026 10:30:00 GMT
Vary: Accept, Accept-Language, Authorization
```

Conditional requests:

```http
GET /orders/123
If-None-Match: "33a64df5..."
→ 304 Not Modified (body empty)

PUT /orders/123
If-Match: "33a64df5..."
→ 412 Precondition Failed (if resource changed)
```

ETags enable optimistic concurrency: client sends `If-Match` on `PUT`/`PATCH`,
server returns 412 on conflict.

## Idempotency

`PUT` and `DELETE` are idempotent by definition. Make `POST` safely retriable:

```http
POST /payments
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

Server stores the key → canonical response for 24 h. Retries return the
cached response. Key collisions with different bodies → 422.

## Search, filter, sort, field selection

```
# Filter
GET /orders?status=open&customer_id=cus_123

# Sort (prefix `-` for desc)
GET /orders?sort=-created_at,customer_id

# Field selection (sparse fieldsets)
GET /orders?fields=id,total_cents,status
GET /orders?exclude=internal_notes

# Full-text search
GET /orders?q=coffee+mug

# Compound
GET /orders?status=open&customer_id=cus_123&sort=-created_at&fields=id,total
```

## Nested collections

Prefer flat routes when relationships are weak:

```
# Strong relationship — nested makes sense
GET /orders/{id}/line-items

# Weak relationship — keep flat
GET /customers/{id}/addresses       # maybe
GET /addresses?customer_id=cus_123  # often better (reusable filter)
```

## Bulk operations

```
# Bulk create
POST /orders/batch
{
  "orders": [ { ... }, { ... }, { ... } ]
}
→ 200 with per-item results
{
  "results": [
    { "index": 0, "status": 201, "id": "ord_1" },
    { "index": 1, "status": 422, "error": { "code": "VALIDATION_FAILED" } }
  ]
}
```

Do not use `/orders?ids=1,2,3` for deletes — clunky and cache-hostile.
Prefer explicit batch endpoints with clear semantics.

## Long-running operations

```http
POST /exports
→ 202 Accepted
Location: /exports/exp_01HBZ...

GET /exports/exp_01HBZ...
→ 200
{
  "id": "exp_01HBZ...",
  "status": "running",          # queued | running | succeeded | failed
  "progress": 0.42,
  "result_url": null
}
```

Polling is fine for most cases; offer webhooks/callbacks for long jobs.

## Rate limiting

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 30
X-RateLimit-Limit: 1000
X-RateLimit-Remaining: 0
X-RateLimit-Reset: 1682957040
```

Document per-plan budgets. Provide a quota endpoint so clients can check
their own usage.

## Common headers

| Category | Headers |
|---|---|
| Identity | `Authorization`, `X-Api-Key` |
| Correlation | `X-Correlation-Id`, `traceparent` |
| Idempotency | `Idempotency-Key` |
| Caching | `Cache-Control`, `ETag`, `If-None-Match`, `If-Match`, `Last-Modified` |
| Rate limit | `Retry-After`, `X-RateLimit-*` |
| Security | `Strict-Transport-Security`, `Content-Security-Policy` |
| Content | `Content-Type`, `Content-Language`, `Content-Encoding` |

## Checklist

- [ ] Resources are plural nouns
- [ ] Methods respect safe/idempotent semantics
- [ ] 201 Created responses set `Location`
- [ ] Errors are RFC 7807 with stable codes
- [ ] Validation uses 422 with a `violations` array
- [ ] Cursor pagination by default
- [ ] Idempotency keys on mutating POSTs
- [ ] ETag + If-Match for optimistic concurrency where needed
- [ ] `X-Correlation-Id` propagated end-to-end
- [ ] Rate limits exposed via headers
- [ ] HTTPS + HSTS enforced
- [ ] `OPTIONS` / CORS handled
