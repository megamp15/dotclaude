---
name: api-designer
description: Design REST (and REST-like) APIs. Resource modeling, HTTP semantics, versioning, pagination, error handling, RFC 7807, idempotency, OpenAPI. Use when designing a new API, reviewing an existing API, or writing an OpenAPI spec. For GraphQL, use graphql-architect.
source: core
triggers: /api-designer, REST API, design an API, API review, OpenAPI, Swagger, API versioning, pagination strategy, error handling strategy, HATEOAS, idempotency key
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/api-designer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# api-designer

You design REST APIs that are boring and correct. Resources are nouns, verbs
are HTTP methods, status codes mean what they say, versioning was decided
before the first client shipped, and errors carry enough detail to debug
without guessing.

## When this skill is the right tool

- Designing a new public or internal REST API
- Reviewing an existing API for consistency and correctness
- Deciding a versioning, pagination, or error-handling strategy
- Writing or reviewing an OpenAPI spec
- Creating API contracts before implementation

**Not for:**
- GraphQL schema design → `graphql-architect`
- System architecture → `architecture-designer`
- Distributed-systems patterns → `microservices-architect`

## Core workflow

1. **Model resources** — nouns, plural, hierarchical only when it expresses a real relationship.
2. **Map operations to HTTP methods** — GET/POST/PUT/PATCH/DELETE, respecting safe and idempotent semantics.
3. **Pick status codes** — the right 2xx/4xx/5xx for each outcome.
4. **Design pagination** — cursor by default for large/real-time; offset only when justified.
5. **Design errors** — RFC 7807 `application/problem+json` with stable error codes.
6. **Pick a versioning strategy** — URI versioning is the default; decide before ship.
7. **Write the OpenAPI spec** — 3.1, examples for every endpoint, schemas named and reused.
8. **Add security** — authentication, authorization per endpoint, rate limits, CORS policy.

## Resource modeling

```
GET    /orders                      # list
POST   /orders                      # create
GET    /orders/{id}                 # read
PATCH  /orders/{id}                 # partial update
DELETE /orders/{id}                 # delete
GET    /orders/{id}/line-items      # nested collection (real relationship)
POST   /orders/{id}/cancellation    # controller-style for non-CRUD ops
```

**Rules:**
- Plural collection names, lowercase, kebab-case for multi-word.
- Max 2–3 levels of nesting.
- Query parameters for filter/sort/select/search, not path params.
- Non-CRUD operations expressed as sub-resources representing the "thing being
  done" (`/orders/{id}/cancellation` > `/orders/{id}/cancel`).

## HTTP methods

| Method | Safe | Idempotent | Typical use |
|---|---|---|---|
| GET | Yes | Yes | Read |
| HEAD | Yes | Yes | Metadata only |
| OPTIONS | Yes | Yes | Discover capabilities |
| POST | No | No | Create, non-idempotent op |
| PUT | No | Yes | Replace full resource |
| PATCH | No | No | Partial update (use JSON Merge Patch or JSON Patch — pick one) |
| DELETE | No | Yes | Remove |

## Status codes

**Use these first; avoid exotic ones.**

| Code | Meaning | Use |
|---|---|---|
| 200 | OK | GET, PUT, PATCH success |
| 201 | Created | POST that creates; set `Location` header |
| 202 | Accepted | Async kickoff; return a job URL |
| 204 | No Content | DELETE success; also PUT/PATCH when returning body is pointless |
| 301 / 308 | Permanent redirect | URL moved |
| 304 | Not Modified | Conditional GET match |
| 400 | Bad Request | Malformed syntax or generic client error |
| 401 | Unauthorized | Missing/invalid auth |
| 403 | Forbidden | Authenticated but not permitted |
| 404 | Not Found | Resource doesn't exist (or shouldn't be visible) |
| 405 | Method Not Allowed | Include `Allow` header |
| 409 | Conflict | State conflict (duplicate, edit conflict) |
| 410 | Gone | Permanently removed; useful for deprecated versions |
| 412 | Precondition Failed | ETag / If-Match mismatch |
| 415 | Unsupported Media Type | Content-Type not accepted |
| 422 | Unprocessable Entity | Syntactically OK but semantically invalid |
| 429 | Too Many Requests | Rate limit; include `Retry-After` |
| 500 | Internal Server Error | Unhandled server bug |
| 502 | Bad Gateway | Upstream failed |
| 503 | Service Unavailable | Maintenance / overload; include `Retry-After` |
| 504 | Gateway Timeout | Upstream timed out |

## Error envelope (RFC 7807)

Use `application/problem+json` for every 4xx/5xx.

```json
{
  "type": "https://api.example.com/errors/order-not-found",
  "title": "Order not found",
  "status": 404,
  "detail": "Order ord_01HBX... does not exist.",
  "instance": "/orders/ord_01HBX...",
  "code": "ORDER_NOT_FOUND",
  "correlation_id": "cor_01HBY..."
}
```

**Rules:**
- `code` is stable, machine-readable, SHOUTY_SNAKE.
- `detail` is human-readable; never include stack traces or PII.
- `correlation_id` is always present and matches the log record.
- For validation, use 422 with a `violations` array:

```json
{
  "type": "https://api.example.com/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "code": "VALIDATION_FAILED",
  "violations": [
    { "field": "email", "code": "INVALID_FORMAT" },
    { "field": "age", "code": "OUT_OF_RANGE", "min": 18, "max": 120 }
  ],
  "correlation_id": "cor_01HBY..."
}
```

## Idempotency

Every mutating `POST` accepts `Idempotency-Key` (client-supplied UUID). The
server stores key + canonical response for 24 hours and returns the cached
response on replay. Do not skimp — this is what makes retries safe.

## Pagination

**Default: cursor-based.**

```http
GET /orders?limit=50&cursor=eyJpZCI6Im9yZF8wMUhCIn0
```

```json
{
  "data": [ ... ],
  "pagination": {
    "limit": 50,
    "has_more": true,
    "next_cursor": "eyJpZCI6Im9yZF8wMUhDIn0",
    "prev_cursor": "eyJpZCI6Im9yZF8wMUhBIn0"
  }
}
```

Use offset/page pagination **only** when the data is small/static, users
need to jump to arbitrary pages, and a COUNT is cheap. See
`references/pagination.md`.

## Versioning

URI versioning is the default:

```
https://api.example.com/v1/orders
```

See `references/versioning.md` for strategy, deprecation lifecycle, sunset
headers, and migration guides.

## Contract-first

Write the OpenAPI spec before the server. It's the contract between teams.

- OpenAPI 3.1 (not 3.0).
- Every endpoint has summary, description, parameters, request/response schemas.
- Every schema is named and reused (`components/schemas`).
- Every endpoint has at least one example request + response.
- `operationId` is a verbNoun (e.g., `listOrders`, `createOrder`).

```yaml
openapi: 3.1.0
info:
  title: Orders API
  version: 1.0.0
servers:
  - url: https://api.example.com/v1
paths:
  /orders:
    get:
      operationId: listOrders
      summary: List orders
      parameters:
        - $ref: '#/components/parameters/Cursor'
        - $ref: '#/components/parameters/Limit'
      responses:
        '200':
          description: Paginated orders
          content:
            application/json:
              schema: { $ref: '#/components/schemas/OrderList' }
```

## Must do

- Use plural resource names.
- Use HTTP methods for their defined semantics (don't `GET` to mutate).
- Return `Location` on `201 Created`.
- Use RFC 7807 for errors with stable `code`s.
- Idempotency keys on mutating POST.
- Cursor pagination for anything that could grow.
- Decide a versioning strategy on day 1.
- Write the OpenAPI spec before the server.
- Require TLS. Set `Strict-Transport-Security`.
- Rate-limit per client with `X-RateLimit-*` headers and `Retry-After` on 429.

## Must not do

- Put verbs in URLs (`/getUser`, `/createOrder`).
- Return 200 for errors. "`"ok": false`" in a 200 breaks every generic client.
- Mix snake_case and camelCase in the same API.
- Deep nesting (`/a/{id}/b/{id}/c/{id}/d/{id}`).
- Break without a version bump.
- Paginate with offset when the table is large and growing.
- Skip `OPTIONS` (CORS) and then wonder why the browser can't call it.

## Output template

```markdown
# API design: <name>

## Resources
| Resource | URL pattern | Owns |
|---|---|---|

## Operations
| Method | Path | Description | Auth | Rate limit |
|---|---|---|---|---|

## Error codes
| Code | Status | Meaning |
|---|---|---|

## Versioning
URI versioning. Current version: v1. Deprecation policy: 6-month sunset with
`Deprecation` + `Sunset` headers.

## Pagination
Cursor-based, default limit 25, max 100.

## Security
- AuthN: <mechanism>
- AuthZ: <model>
- Rate limit: <per-client budget>
```

## References

| Topic | File |
|---|---|
| REST resource + method patterns, HATEOAS, cache headers | `references/rest-patterns.md` |
| Versioning strategies, deprecation lifecycle | `references/versioning.md` |
| Pagination strategies (cursor, offset, keyset) | `references/pagination.md` |
| OpenAPI + error handling patterns | `references/openapi-and-errors.md` |
