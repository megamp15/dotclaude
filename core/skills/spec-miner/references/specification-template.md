---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/spec-miner/references/specification-template.md
ported-at: 2026-04-17
adapted: true
---

# Reverse-spec template

Save as `specs/<project-or-feature>-reverse-spec.md`.

```markdown
# Reverse spec: <name>

**Generated:** <date>
**Source revision:** <git short sha>
**Scope:** <full system / service / feature>
**Author / analyst:** <name>

## 1. Executive summary

<2–3 sentences: what this system is, its primary purpose, the single most
important thing a new owner should know about it.>

## 2. Stack + topology

| Layer | Technology | Notes |
|---|---|---|
| Language / runtime | | |
| Web / RPC frameworks | | |
| Data stores | | |
| Caches | | |
| Queues / streams | | |
| External services | | |
| Infra (build, run, deploy) | | |
| Observability | | |

## 3. Module map

```
src/
├── api/           # HTTP handlers
├── domain/        # business logic
├── infra/         # DB, queue, external clients
├── workers/       # background jobs
└── cli/           # operational commands
```

Per top-level module: 1-line purpose + notable files.

## 4. Entry points

| Entry point | Kind | File | Purpose |
|---|---|---|---|
| POST /orders | HTTP | src/api/orders.py:L22 | Create order |
| order-created | Queue | src/workers/order_created.py:L18 | Fulfillment |
| /admin/migrate | CLI | src/cli/admin.py:L10 | DB migrations |

## 5. Observed functional requirements (EARS)

Every FR includes a code citation. Mark **observed** vs. **inferred**.

**FR-ORDER-001 — Create order (observed)**
*EARS:* When POST /orders is called with a valid body, the system shall
create an order record and emit `Order.Created`.
*Evidence:* `src/api/orders.py:L22-58`; `src/domain/orders.py:L104`.

**FR-ORDER-002 — Out-of-stock (observed)**
*EARS:* While any line item has stock < requested quantity, when POST
/orders is called, the system shall return 409 with `code: OUT_OF_STOCK`.
*Evidence:* `src/domain/orders.py:L131-145`.

**FR-AUTH-001 — Auth required (observed)**
*EARS:* When a request to any /orders endpoint lacks a valid Bearer token,
the system shall return 401.
*Evidence:* `src/api/middleware.py:L18`.

…

## 6. Inferred behavior

> Consistent with the code but not directly proven. Product confirmation
> required.

- **FR-CART-x — Coupon stacking (inferred)** — cart logic does not prevent
  stacking multiple coupons. `src/domain/cart.py:L210`.
- **FR-ADMIN-x — Soft delete (inferred)** — `users.deleted_at` exists but
  no endpoint sets it. `src/models/user.py:L12`.

## 7. Non-functional observations

| NFR | Observation | Evidence |
|---|---|---|
| Availability | Single replica, no HA | `docker-compose.yml` |
| Latency | p95 ~300 ms (prod Grafana) | `infra/grafana/*.json` |
| Scalability | No horizontal scaling config | — |
| Security | Bcrypt cost 12; JWT 15 min | `src/auth/*` |
| Rate limit | None found | — |
| Observability | Structured JSON logs via structlog | `src/obs/logging.py` |
| Error tracking | Sentry wired for unhandled only | `src/obs/sentry.py:L20` |

## 8. Data model

- **users** — id, email, password_hash, created_at, deleted_at
- **orders** — id, user_id, total, status, created_at
- **order_items** — order_id, sku, qty, unit_price
- **events** — id, type, payload, created_at (audit)

<optional: ER diagram>

## 9. External integrations

| System | Purpose | Auth | Failure handling |
|---|---|---|---|
| Stripe | Payments | API key (env) | Retries 3×; dead-letter on fail |
| SES | Email | IAM role | Best-effort; no retry |
| S3 | Files | IAM role | Raises on 5xx |

## 10. Inferred acceptance criteria

- [ ] Authenticated user can POST /orders → 201 with order resource.
- [ ] Unauthenticated POST /orders → 401.
- [ ] Out-of-stock → 409 with code `OUT_OF_STOCK`.
- [ ] Successful order emits `Order.Created` exactly once.

## 11. Uncertainties + open questions

| # | Question | Impact | Who can answer |
|---|---|---|---|
| Q1 | Coupon stacking — intended or a bug? | Pricing correctness | Product |
| Q2 | Is `/admin/debug` exposed in prod? | Security | Ops |
| Q3 | Retention on `events` table? | Compliance | Data |

## 12. Recommendations

- Add rate limiting on `/auth/login`.
- Document + test `OUT_OF_STOCK` flow (only one integration test today).
- Consolidate `logging` and `structlog` usage.
- Add runbook for failed `Order.Created` emission.

## 13. Code map appendix

<per-module table with purpose, key symbols, dependencies — fill only when
the spec will be handed off to someone who needs full code orientation.>
```
