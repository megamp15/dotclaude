---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/feature-forge/references/ears-syntax.md
ported-at: 2026-04-17
adapted: true
---

# EARS syntax

EARS (Easy Approach to Requirements Syntax) forces clarity. Each requirement
reads as one of five patterns, so reviewers, testers, and implementers read
it the same way.

## Five patterns

| Type | Pattern | Use when |
|---|---|---|
| Ubiquitous | `The system shall <action>` | Always true |
| Event-driven | `When <trigger>, the system shall <action>` | On a trigger |
| State-driven | `While <state>, the system shall <action>` | Continuous state |
| Conditional | `While <state>, when <trigger>, the system shall <action>` | State + trigger |
| Optional | `Where <feature enabled>, the system shall <action>` | Gated by flag/config |

## Ubiquitous

Applies always, no trigger or state.

```
The system shall encrypt passwords at rest using bcrypt with cost ≥ 12.
The system shall return UTC timestamps for all API responses.
```

## Event-driven

Triggered by a discrete event.

```
When POST /auth/login is called with valid credentials, the system shall
return a JWT access token (15 min) and a refresh token (7 days).

When an invoice reaches its due date without payment, the system shall send
a reminder email to the billing contact.
```

## State-driven

Active while a state holds.

```
While the user is logged in, the system shall display the user's avatar in
the top-right navigation.

While the job queue has pending items, the system shall process one item
every 2 seconds.
```

## Conditional (most common)

State + event — the classic "given X, when Y, then Z".

```
While the cart contains at least one item, when the user clicks Checkout,
the system shall navigate to the payment page.

While a user has admin role, when DELETE /users/:id is called, the system
shall soft-delete the user and return 204.
```

## Optional

Behavior gated by a feature flag, subscription tier, or configuration.

```
Where 2FA is enabled for the user, the system shall require a verification
code on login.

Where the customer is on the Pro plan, the system shall allow up to 100
concurrent API keys.
```

## Worked examples

### Authentication

```
FR-AUTH-001 — Login
When POST /auth/login is called with valid credentials, the system shall
return a 200 with a JWT access token (15 min) and a refresh token (7 days).

FR-AUTH-002 — Invalid credentials
When POST /auth/login is called with invalid credentials, the system shall
return 401 and increment the failed-login counter for that email.

FR-AUTH-003 — Lockout
While the failed-login count for an email exceeds 5 within 15 minutes,
when /auth/login is called for that email, the system shall return 423 and
require a password reset.

FR-AUTH-004 — 2FA (optional)
Where 2FA is enabled for the user, the system shall require a valid
verification code before issuing tokens.
```

### Orders

```
FR-CART-001 — Add to cart
While the user is authenticated, when POST /cart/items is called with a
valid SKU and quantity, the system shall add the item to the cart and
return the updated cart total.

FR-CART-002 — Apply coupon
While the cart contains items and the coupon is valid, when POST
/cart/coupons is called, the system shall reduce the cart total by the
coupon amount and return the updated totals.

FR-ORDER-001 — Place order
While the cart is non-empty and the payment method is valid, when POST
/orders is called, the system shall create the order, charge the payment
method, emit Order.Placed, and return 201 with the order resource.
```

### Data export

```
FR-EXPORT-001 — Request export
While the user has data:export permission, when POST /exports is called,
the system shall create an export job and return 202 with a job URL.

FR-EXPORT-002 — Large export
While an export would exceed 10 MB, the system shall process it as a
background job and notify the user by email when ready.

FR-EXPORT-003 — Deletion
When an export is successfully downloaded, the system shall delete the
generated file within 24 hours.
```

## Authoring rules

- Use "shall" — not "should", "will", "can", or "may".
- One requirement per line; don't combine with "and also".
- Name actors precisely — "the user", "the admin", "the cron", not "someone".
- Name HTTP methods and paths explicitly for API requirements.
- Include concrete thresholds (15 min, 10 MB, 5 attempts) — not "a short
  time" or "a few".
- Each requirement has a unique ID: `FR-<AREA>-<NNN>` (e.g. `FR-AUTH-001`).

## Common mistakes

- **Compound requirements.** "The system shall do X and also Y" — split into two.
- **Subjective outcomes.** "Fast", "intuitive", "user-friendly" — rephrase
  with measurable criteria (p95 < 200 ms, zero training clicks, etc.).
- **Implementation leakage.** "The system shall use Redis to cache…" —
  requirements are what, not how. If Redis is forced by constraint, note
  that under constraints, not in an FR.
- **Hidden assumptions.** "The system shall send an email" — via what service?
  to whom? triggered when? Be explicit.

## Quick chooser

| Feel | Pattern |
|---|---|
| "Always true" | Ubiquitous |
| "Happens on X" | Event-driven |
| "While X is happening" | State-driven |
| "Given X, when Y" | Conditional |
| "If feature is on" | Optional |
