---
name: fullstack-guardian
description: Build a full-stack feature (backend + frontend) with security baked in at every layer. Forces three perspectives on every change — Frontend, Backend, Security — and produces a short design + implementation with auth, input validation, parameterized queries, output encoding, and error handling addressed. Use for feature work that spans API + UI, authenticated endpoints with views, or end-to-end data flows. Distinct from feature-forge (spec-only), architecture-designer (system-level), and stack-specific skills (patterns).
source: core
triggers: /fullstack, full stack feature, implement feature end-to-end, frontend and backend, API and UI, authenticated route plus view, CRUD feature, end-to-end implementation
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/fullstack-guardian
ported-at: 2026-04-17
ported-sha: main
adapted: true
note: Intentionally thin. Stack-specific patterns live in stacks/<stack>/. Deep security review lives in security (audit mode).
---

# fullstack-guardian (thin)

You implement a full-stack feature as **one change** spanning backend and
frontend, with security treated as a first-class layer — not a "pass before
merge". Every change is viewed through three lenses:

1. **Backend** — data model, endpoint, domain logic, queries, events.
2. **Frontend** — component, state, API call, error UX, accessibility.
3. **Security** — authn, authz, validation, output encoding, logging,
   response shape.

You do **not** do deep architectural design (that's `architecture-designer`)
or full security audits (that's `security (audit mode)`). You ship a reviewable
feature with security done correctly end-to-end.

## When this skill is the right tool

- Feature touches both API and UI.
- New authenticated endpoint + the view that calls it.
- CRUD feature with a form + list + detail.
- Real-time feature spanning backend push + frontend subscription.

**Not for:**
- Pure backend refactor → `refactor` + stack skill.
- Pure frontend change → stack skill (e.g. `stacks/react/`).
- Unknown scope → run `feature-forge` first.
- Significant architecture decisions → `architecture-designer`.
- Full security posture review → `security (audit mode)`.

## Core workflow

### 1. Intake

- Read the spec or user request. If no spec, run `feature-forge` first.
- List the surface touched: endpoints, DB tables, components, routes.
- Identify the stacks involved and load their rules
  (e.g. `stacks/react/`, `stacks/fastapi/`, `stacks/nextjs/`).

### 2. Three-perspective design (short)

Write `specs/<feature>-design.md` with three sections. Keep it tight —
1–2 pages, not a novel. See `references/design-template.md`.

- **Backend** — schema change, endpoints, events, validation, error codes.
- **Frontend** — routes, components, data fetching, loading/error states.
- **Security** — authn, authz model, input validation, output shape,
  audit/logging, abuse/rate limits.

### 3. Security checkpoint (before coding)

Walk `references/security-checklist.md`. Do not skip. Confirm on paper:

- Who can call this?
- What do they receive?
- What input do we trust?
- What do we log?

### 4. Implement incrementally

- **Backend first**: schema → endpoint → unit tests → integration test.
- **Frontend second**: types (shared if possible) → fetcher → component →
  states (loading, empty, error).
- **Wire security at every layer** — not as a final pass.

### 5. Verify + hand off

- Lint, typecheck, tests pass.
- Manual walk-through for each user role (including unauthenticated).
- Hand off to `pr-review` / `ship` for the review and merge loop.

## Three-perspective example

A minimal authenticated endpoint + view.

### Backend — authenticated, parameterized, scoped response

```python
@router.get("/users/{user_id}/profile", dependencies=[Depends(require_auth)])
async def get_profile(
    user_id: int,
    current_user: User = Depends(get_current_user),
) -> ProfileResponse:
    if current_user.id != user_id and not current_user.is_admin:
        raise HTTPException(403, "forbidden")

    row = await db.fetch_one(
        "SELECT id, name, email FROM users WHERE id = :id",
        {"id": user_id},
    )
    if row is None:
        raise HTTPException(404, "not found")

    return ProfileResponse(**row)
```

### Frontend — types shared, errors handled, auth in the client

```typescript
export async function fetchProfile(userId: number): Promise<Profile> {
  if (!Number.isInteger(userId) || userId <= 0) {
    throw new Error("invalid user id");
  }
  const res = await apiFetch(`/users/${userId}/profile`);
  if (!res.ok) {
    throw new ApiError(res.status, await safeText(res));
  }
  return res.json();
}
```

### Security notes

- Authentication enforced via `require_auth` dependency. The client's
  auth header is a convenience, not the gate.
- Authorization: explicit comparison to `current_user.id` + admin bypass.
  Denied **before** the DB query — no timing leak via 404 vs. 403.
- Parameterized query; no string interpolation.
- Response schema (`ProfileResponse`) explicitly excludes sensitive fields
  (no `password_hash`, no `session_token`).
- Client-side validation is a UX nicety, not a trust boundary.

## Rules

### Must do

- Address all three perspectives on every change.
- Validate input on the server (client validation is UX only).
- Use parameterized queries / prepared statements / ORM — never interpolate.
- Sanitize output; never return raw DB rows to clients.
- Define an explicit response schema per endpoint.
- Handle the unauthenticated, forbidden, and not-found cases explicitly.
- Log security-relevant events: auth failures, privilege escalations,
  admin actions, bulk reads, destructive operations.
- Write the design before writing code. If you can't write 1 page of
  design, the feature isn't ready.
- Test each layer as you build (unit → integration → UI smoke).

### Must not

- Trust client-side validation alone.
- Return untyped / unshaped responses.
- Leak sensitive fields (`password_hash`, `session_token`, internal IDs
  where not needed, PII beyond what the caller is authorized for).
- Hard-code secrets, tokens, or URLs.
- Skip error states on the frontend (loading, empty, error, retry).
- Combine authn and authz into one check (they're different failures).
- Ship a "happy path only" PR.

## References

| Topic | File |
|---|---|
| Design template (backend / frontend / security — 1-page) | `references/design-template.md` |
| Security checklist (per feature, before coding) | `references/security-checklist.md` |
| Error handling layering patterns | `references/error-handling.md` |

## See also

| Need | Skill |
|---|---|
| Write the spec | `feature-forge` |
| Understand existing behavior | `spec-miner` |
| Ship the change | `ship` |
| Review the change | `pr-review` |
| Deep security posture review | `security (audit mode)` |
| Stack-specific patterns | `stacks/<stack>/` |
