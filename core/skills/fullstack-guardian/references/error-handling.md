---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/fullstack-guardian/references/error-handling.md
ported-at: 2026-04-17
adapted: true
---

# Error handling — layered

Errors are a cross-cutting concern. Handle each layer at its own altitude;
don't let backend error shapes leak into the UI and don't let UI error
strings leak back into logs.

## Backend layering

### 1. Domain errors (typed, not `Exception`)

Represent business failures with specific types:

```python
class DomainError(Exception): ...

class OutOfStockError(DomainError):
    def __init__(self, sku: str, available: int):
        self.sku = sku
        self.available = available
        super().__init__(f"sku {sku} has only {available} available")

class InvalidCouponError(DomainError): ...
class PaymentDeclinedError(DomainError): ...
```

### 2. Validation errors

Use the framework's validation layer (pydantic, zod, class-validator,
FluentValidation). Return 400 (shape) or 422 (semantic) with field-level
details.

### 3. Infrastructure errors

Database, network, external API failures. Wrap at the boundary so the
domain doesn't leak driver exceptions.

```python
try:
    return await db.fetch_one(...)
except asyncpg.PostgresError as e:
    raise InfraError("db unavailable") from e
```

### 4. Boundary — HTTP layer

One adapter maps domain / validation / infra errors to HTTP status +
response envelope:

```python
@app.exception_handler(OutOfStockError)
async def _(request, exc: OutOfStockError):
    return JSONResponse(
        status_code=409,
        content=error_body(
            status=409,
            code="OUT_OF_STOCK",
            title="Item is out of stock",
            detail=str(exc),
            fields={"sku": exc.sku, "available": exc.available},
        ),
    )
```

Never let a raw driver exception or stack trace reach the client.

### 5. Error envelope (consistent)

```json
{
  "type": "about:blank",
  "title": "Item is out of stock",
  "status": 409,
  "code": "OUT_OF_STOCK",
  "detail": "sku A1 has only 0 available",
  "instance": "/orders/abc123",
  "fields": { "sku": "A1", "available": 0 }
}
```

Per RFC 7807 (`application/problem+json`). See `architect` rest-api mode for the full
error spec.

## Frontend layering

### 1. Network layer — normalize

Wrap `fetch` so every caller sees the same error shape.

```typescript
export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
    message: string,
    public fields?: Record<string, unknown>,
  ) { super(message); }
}

export async function apiFetch(path: string, init?: RequestInit) {
  const res = await fetch(path, init);
  if (!res.ok) {
    let body: any = {};
    try { body = await res.json(); } catch {}
    throw new ApiError(
      res.status,
      body.code ?? "UNKNOWN",
      body.title ?? res.statusText,
      body.fields,
    );
  }
  return res;
}
```

### 2. Component layer — states

Every data-fetching component handles four states: **loading**, **empty**,
**error**, **success**. Not handling all four is a bug.

```tsx
function OrderList() {
  const { data, error, isLoading } = useOrders();
  if (isLoading) return <Skeleton />;
  if (error) return <ErrorBanner error={error} onRetry={retry} />;
  if (!data || data.length === 0) return <EmptyState />;
  return <OrderTable rows={data} />;
}
```

### 3. Form layer — field-level

Map backend `fields` from the error envelope to form field errors:

```tsx
catch (err) {
  if (err instanceof ApiError && err.code === "VALIDATION") {
    for (const [field, message] of Object.entries(err.fields ?? {})) {
      form.setError(field, { message: String(message) });
    }
    return;
  }
  toastError(err);
}
```

### 4. Global — toast + reporter

Uncaught errors → generic toast, report to error tracker (Sentry etc.),
**do not** show stack traces to users.

## Logging

### Backend

- Log at the boundary that decided the outcome (not at every layer).
- One structured log line per request with: method, path, status, duration,
  correlation ID, actor, error code (if any).
- Unexpected errors log at `error` with stack; expected domain errors log
  at `info` or `warn`.
- Never log secrets, cookies, or full request bodies from auth endpoints.

### Frontend

- Report uncaught render errors + unhandled promise rejections.
- Attach correlation ID from the response so support can trace.
- Scrub PII before reporting.

## Retry + idempotency

- Retry only on safe failures (network, 5xx, 429 after backoff).
- Never retry on 4xx — it's deterministic.
- Use `Idempotency-Key` on state-changing POSTs so retries don't duplicate.
- Exponential backoff with jitter. Cap attempts (e.g. 3).

## User-visible messages

- Plain language: "This item is out of stock" — not "409 CONFLICT".
- No internal IDs, SQL snippets, or stack frames.
- Suggest a next action: retry, edit input, contact support with a
  correlation ID.

## Anti-patterns

- Catching and ignoring exceptions to "keep the UI clean".
- Mapping all errors to a single generic "Something went wrong".
- Returning 200 with an error body.
- Different error envelope shapes per route.
- Logging the entire request body (PII + secret leak risk).
- Retrying non-idempotent writes without an idempotency key.
