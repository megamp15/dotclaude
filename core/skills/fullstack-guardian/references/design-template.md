---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/fullstack-guardian/references/design-template.md
ported-at: 2026-04-17
adapted: true
---

# Full-stack design template

Keep it to **1–2 pages**. If you need more, the feature is too large and
should be split. Save as `specs/<feature>-design.md`.

```markdown
# Design: <feature name>

**Spec:** <link to feature-forge spec, if any>
**Owner:** <name>
**Target release:** <version / date window>
**Status:** draft / in review / approved

## Summary
<1–2 sentences: what we're building and why.>

## Surface touched

| Layer | Components |
|---|---|
| API endpoints | `POST /orders`, `GET /orders/{id}` |
| DB tables | `orders`, `order_items` (new), `events` (append) |
| Events | `Order.Created`, `Order.Failed` |
| Routes | `/orders/new`, `/orders/:id` |
| Components | `OrderForm`, `OrderSummary`, `OrderList` |

## Backend

### Data model
<new tables, columns, indexes, migrations order, rollback plan>

### Endpoints

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | /orders | user | Idempotency-Key supported |
| GET | /orders/{id} | owner or admin | |

For each endpoint:
- **Request shape** (fields, types, validation)
- **Response shape** (success + error envelope)
- **Error codes** (400 VALIDATION, 401 UNAUTH, 403 FORBIDDEN, 404 NOT_FOUND,
  409 CONFLICT, 422 BUSINESS_RULE, 5xx)
- **Side effects** (DB writes, events emitted, cache invalidated)
- **Idempotency**: keyed? safe to retry?

### Business rules
<short prose — what invariants matter>

### Observability
<metrics, log fields, traces>

## Frontend

### Routes + layout
<which pages change, nav updates>

### Components

| Component | Purpose | Data source |
|---|---|---|
| OrderForm | Create order | POST /orders |
| OrderSummary | Show result | GET /orders/{id} |

### State + data fetching
- Library: <SWR / React Query / Apollo / stack default>
- Loading state: <skeleton / spinner>
- Empty state: <message + CTA>
- Error state: <recoverable message, retry>

### Accessibility
- Focus management on form submit.
- Error messages associated via `aria-describedby`.
- Color contrast ≥ WCAG AA.
- Keyboard flow verified.

## Security

### Authentication
<mechanism (session, JWT), token lifetime, rotation>

### Authorization
<model: owner, role, scope, tenant; where enforced>

### Input validation
<client (UX) + server (trust boundary); library used>

### Output encoding
<response schema; no raw rows; no stray fields>

### Sensitive data
<what is/isn't returned; how it's redacted from logs>

### Rate limiting / abuse
<per-user limit, per-IP, idempotency window>

### Audit
<events logged, who/what/when fields, retention>

### Threat model sketch
- <top risk 1> → <mitigation>
- <top risk 2> → <mitigation>

## Rollout

- Feature flag: `<key>`, default off, staged.
- Migration order: <additive → code → switch → cleanup>.
- Rollback plan: <revert code; migrations are additive; data cleanup step>.

## Test plan

- Unit: <list>
- Integration: <list>
- E2E happy path: <scenario>
- Negative paths: unauthenticated, forbidden, validation error,
  conflict, server error.
- Accessibility smoke: keyboard flow, screen reader labels.

## Risks + open questions

| # | Item | Impact | Owner |
|---|---|---|---|
| R1 | <risk> | <impact> | <owner> |
| Q1 | <open question> | — | <owner> |
```

## Guidance

- **Every section short.** 3–8 bullet points each is plenty.
- **Never skip Security.** If a section says "N/A", justify why in one
  sentence. "No security impact" is almost never true end-to-end.
- **No implementation details** beyond what affects design decisions. Save
  the code for the PR.
- **Link, don't copy.** Refer to the feature-forge spec and existing ADRs
  instead of repeating them.
- **Deprecate on the way in.** If this design replaces an older pattern,
  mark the predecessor deprecated with a migration note.
