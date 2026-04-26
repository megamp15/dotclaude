---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/api-designer/references
ported-at: 2026-04-17
adapted: true
---

# OpenAPI + error handling

## OpenAPI baseline

Use OpenAPI 3.1. Store at `docs/api/openapi.yaml` with one file per major
version.

```yaml
openapi: 3.1.0
info:
  title: Orders API
  version: 1.0.0
  description: |
    The Orders API manages customer orders, line items, and fulfillment.
  contact:
    name: Platform team
    email: platform@example.com
  license:
    name: Apache-2.0
servers:
  - url: https://api.example.com/v1
    description: Production
  - url: https://api-staging.example.com/v1
    description: Staging

tags:
  - name: orders
    description: Order lifecycle

paths:
  /orders:
    get:
      tags: [orders]
      operationId: listOrders
      summary: List orders
      description: Returns a paginated list of orders the caller can see.
      parameters:
        - $ref: '#/components/parameters/Cursor'
        - $ref: '#/components/parameters/Limit'
        - name: status
          in: query
          schema: { $ref: '#/components/schemas/OrderStatus' }
      responses:
        '200':
          description: Paginated orders
          content:
            application/json:
              schema: { $ref: '#/components/schemas/OrderList' }
              examples:
                default:
                  $ref: '#/components/examples/OrderListExample'
        '401': { $ref: '#/components/responses/Unauthorized' }
        '429': { $ref: '#/components/responses/RateLimited' }

components:
  parameters:
    Cursor:
      name: cursor
      in: query
      schema: { type: string }
      description: Opaque cursor from a previous response.
    Limit:
      name: limit
      in: query
      schema: { type: integer, minimum: 1, maximum: 100, default: 25 }

  schemas:
    Order:
      type: object
      required: [id, status, total_cents, created_at]
      properties:
        id: { type: string, example: ord_01HBX... }
        status: { $ref: '#/components/schemas/OrderStatus' }
        total_cents: { type: integer, format: int64 }
        currency: { type: string, example: USD }
        created_at: { type: string, format: date-time }
    OrderStatus:
      type: string
      enum: [pending, paid, shipped, cancelled]
    OrderList:
      type: object
      required: [data, pagination]
      properties:
        data:
          type: array
          items: { $ref: '#/components/schemas/Order' }
        pagination: { $ref: '#/components/schemas/Pagination' }
    Pagination:
      type: object
      properties:
        limit: { type: integer }
        has_more: { type: boolean }
        next_cursor: { type: string, nullable: true }
        prev_cursor: { type: string, nullable: true }

    Problem:
      type: object
      description: RFC 7807 problem details
      required: [type, title, status, code, correlation_id]
      properties:
        type: { type: string, format: uri }
        title: { type: string }
        status: { type: integer }
        detail: { type: string }
        instance: { type: string }
        code: { type: string, example: ORDER_NOT_FOUND }
        correlation_id: { type: string }
    ValidationProblem:
      allOf:
        - $ref: '#/components/schemas/Problem'
        - type: object
          properties:
            violations:
              type: array
              items:
                type: object
                required: [field, code]
                properties:
                  field: { type: string }
                  code: { type: string }

  responses:
    Unauthorized:
      description: Authentication required
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
    RateLimited:
      description: Too many requests
      headers:
        Retry-After: { schema: { type: integer }, description: Seconds }
      content:
        application/problem+json:
          schema: { $ref: '#/components/schemas/Problem' }
```

## Rules

- One OpenAPI file per major version.
- `operationId` is `verbNoun` and unique across the spec.
- Every schema is named; inline schemas only for trivial helpers.
- Every endpoint has a description, examples, and error responses.
- `components/responses` for reusable responses (401, 403, 404, 429).
- CI validates the spec on every PR (use `openapi-cli`/`redocly`/`spectral`).
- Generated SDKs come from the spec, not hand-written.

## Error handling (RFC 7807)

One error envelope across the entire API:

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

### Field rules

| Field | Required | Rule |
|---|---|---|
| `type` | ✓ | Stable URI to docs for this error class |
| `title` | ✓ | Short human-readable summary |
| `status` | ✓ | HTTP status |
| `detail` | — | Context; no PII, no stack traces |
| `instance` | — | URI of the specific occurrence |
| `code` | ✓ | Stable, SHOUTY_SNAKE_CASE, documented |
| `correlation_id` | ✓ | Matches log records; propagated from `X-Correlation-Id` |

### Validation errors (422)

```json
{
  "type": "https://api.example.com/errors/validation",
  "title": "Validation failed",
  "status": 422,
  "code": "VALIDATION_FAILED",
  "correlation_id": "cor_01HBY...",
  "violations": [
    { "field": "email", "code": "INVALID_FORMAT" },
    { "field": "age", "code": "OUT_OF_RANGE", "min": 18, "max": 120 }
  ]
}
```

### Error-code catalog

Keep a single source of truth:

```markdown
# Error codes (v1)

| Code | Status | Meaning |
|---|---|---|
| UNAUTHENTICATED | 401 | Missing or invalid credentials |
| FORBIDDEN | 403 | Authenticated but not permitted |
| ORDER_NOT_FOUND | 404 | Order does not exist or is hidden |
| VALIDATION_FAILED | 422 | Request body failed validation |
| IDEMPOTENCY_CONFLICT | 422 | Idempotency-Key reused with different body |
| RATE_LIMITED | 429 | Over quota; see Retry-After |
| INTERNAL | 500 | Unhandled server error |
```

Each `type` URI maps to a page in the catalog with examples and remediation.

### Do not

- Return 200 with `"ok": false`.
- Leak stack traces or internal identifiers.
- Change the semantics of `code` across versions — codes are part of the contract.
- Use vague `GENERIC_ERROR` for everything — that forces every client to
  parse `detail` strings.

## Cross-cutting concerns

- **Correlation IDs:** propagate `X-Correlation-Id` in and out. Include it in
  every log record and every error body.
- **Structured logging:** log `method`, `path`, `status`, `duration_ms`,
  `correlation_id`, `user_id`, `error_code` when present.
- **Tracing:** accept and propagate `traceparent` (W3C). Your API gateway
  and services should already handle this.

## OpenAPI + CI checklist

- [ ] Spec validates (`redocly lint` / `spectral lint`)
- [ ] No breaking changes without a version bump (`oasdiff` in CI)
- [ ] Mocked server passes contract tests
- [ ] SDKs regenerated and tagged with the spec version
- [ ] `/openapi.yaml` served publicly (for public APIs) or from an internal docs portal
