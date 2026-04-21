---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/spec-miner/references/ears-format.md
ported-at: 2026-04-17
adapted: true
---

# EARS format (for observed behavior)

Use EARS to write what the code *does*, not what it *should* do. If the
behavior isn't proven by the code, it goes in "Uncertainties", not here.

## Five patterns

| Type | Pattern | Use when |
|---|---|---|
| Ubiquitous | `The system shall <action>` | Always true |
| Event-driven | `When <trigger>, the system shall <action>` | On a discrete trigger |
| State-driven | `While <state>, the system shall <action>` | Continuous state |
| Conditional | `While <state>, when <trigger>, the system shall <action>` | State + trigger |
| Optional | `Where <feature enabled>, the system shall <action>` | Gated by flag/config |

## Ubiquitous

```
The API shall return responses as application/json.
The system shall hash passwords with bcrypt cost ≥ 12.
```

## Event-driven

```
When POST /auth/login is called with valid credentials, the system shall
return 200 with an access token.

When a request lacks a valid Bearer token, the system shall return 401.
```

## State-driven

```
While the worker pool is full, the system shall queue new jobs in Redis.

While maintenance_mode is true, the system shall reject all write requests
with 503.
```

## Conditional

```
While the user has role=admin, when DELETE /users/:id is called, the system
shall soft-delete the user and return 204.

While the feature flag `exports_v2` is enabled, when POST /exports is
called, the system shall use the new exporter pipeline.
```

## Optional

```
Where the STRIPE_WEBHOOK_SECRET env var is set, the system shall verify
Stripe webhook signatures.
```

## Requirement + evidence

Every reverse-engineered requirement must cite its source:

```
FR-ORDER-001 — Create order (observed)
When POST /orders is called with a valid body, the system shall create
an order record and emit `Order.Created`.
Evidence: `src/api/orders.py:L22-58`; `src/domain/orders.py:L104`.
```

## Observed vs. inferred

- **Observed** — the code path actively does this. A test, a log, or
  direct reading proves it.
- **Inferred** — the code is consistent with this behavior but doesn't
  unambiguously prove it (e.g. a helper exists but no caller was found).

Mark inferred requirements explicitly:

```
FR-CART-002 — Coupon stacking (inferred)
The cart domain accepts multiple coupons without a stacking check.
Evidence: `src/domain/cart.py:L210-240`. Requires product confirmation.
```

## Common mistakes

- Writing what you *think* the system does from reading README — not evidence.
- Skipping error paths because the happy path was obvious.
- Combining multiple behaviors in one FR (split them).
- Omitting negative paths (401, 403, 404, 409, 422, 5xx).
- Forgetting side effects (events emitted, cache invalidations, audit log rows).

## Quick reference

| Situation | Pattern |
|---|---|
| "Always returns JSON" | Ubiquitous |
| "On POST /x, it does Y" | Event-driven |
| "While maintenance mode" | State-driven |
| "Admin can DELETE /users" | Conditional |
| "If flag X is set" | Optional |
