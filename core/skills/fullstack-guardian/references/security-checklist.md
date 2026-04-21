---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/fullstack-guardian/references/security-checklist.md
ported-at: 2026-04-17
adapted: true
---

# Per-feature security checklist

Walk this before writing code. Don't skip. "Not applicable" requires a
one-sentence justification.

## Authentication

- [ ] Who can call this? (public, authenticated, MFA-gated, service-to-service)
- [ ] Which mechanism? (session cookie, JWT, API key, mTLS)
- [ ] Is it enforced server-side?
- [ ] Are tokens short-lived with a refresh path?
- [ ] Are failures distinguishable in a way that helps attackers? (uniform
      401 without enumerating whether the user exists)

## Authorization

- [ ] Model: owner / role / scope / tenant — which?
- [ ] Enforced at one clear boundary (middleware, dependency, policy)?
- [ ] Checked **before** expensive work (avoid timing/oracle leaks)?
- [ ] 403 vs 404 decision made deliberately?
- [ ] Admin / bypass path audited?
- [ ] Multi-tenant isolation: tenant ID comes from auth context, **never**
      from user-supplied input?

## Input validation

- [ ] Schema validation on the server for every request body / query /
      param (pydantic, zod, joi, FluentValidation, etc.).
- [ ] Size/length limits on strings, arrays, and file uploads.
- [ ] Type + range checks on numbers and IDs.
- [ ] Enum values are validated (not free-form strings).
- [ ] No free-form fields inserted into queries, shells, or paths.
- [ ] Client-side validation is a UX helper only, not a trust boundary.

## Data access

- [ ] Parameterized queries / prepared statements / ORM — no string
      interpolation.
- [ ] Tenant / owner filter on every query returning multi-tenant data.
- [ ] No `SELECT *` into a response.
- [ ] No ORM lazy-loading that crosses the trust boundary.
- [ ] Soft-delete and hard-delete paths audited.

## Output encoding + response shape

- [ ] Explicit response schema per endpoint (no raw rows / models).
- [ ] Sensitive fields excluded: password hashes, session tokens,
      secrets, internal IDs (when not needed), PII beyond what caller
      may see.
- [ ] Error responses follow a single envelope; never leak stack traces
      or DB messages.
- [ ] UI escapes user-generated content (framework defaults are usually
      enough; verify for `dangerouslySetInnerHTML` / `v-html`).

## Secrets + config

- [ ] No hardcoded secrets in code, tests, or config.
- [ ] Secrets sourced from the platform secret store.
- [ ] Logs scrub tokens, cookies, Authorization headers, `password`,
      `token`, `secret` fields.

## Rate limiting + abuse

- [ ] Auth endpoints: per-email + per-IP limits, lockout on sustained
      failure.
- [ ] Write-heavy endpoints: per-user limits.
- [ ] Idempotency-Key accepted where retries are plausible.
- [ ] Public or unauthenticated endpoints: per-IP limit + captcha/proof
      where reasonable.

## Session + cookies

- [ ] Cookies: `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict` where
      applicable).
- [ ] CSRF protected for cookie-auth routes that perform state change.
- [ ] Session rotation on privilege elevation (login, role change).

## Transport + headers

- [ ] TLS enforced (HSTS, no mixed content).
- [ ] Content Security Policy set and tight.
- [ ] `X-Content-Type-Options: nosniff`, `Referrer-Policy`,
      `Permissions-Policy` as appropriate.
- [ ] CORS restricted to known origins, methods, and headers.

## File upload / download

- [ ] MIME + magic-byte verification, not just extension.
- [ ] Size limits enforced at ingress (not only in app).
- [ ] Stored outside the webroot / behind signed URLs.
- [ ] Downloads use `Content-Disposition: attachment` with sanitized names.

## Logging + audit

- [ ] Security-relevant events logged (authn fail, authz fail, admin
      action, bulk read, destructive op).
- [ ] Log fields include actor, target, action, correlation ID, IP.
- [ ] PII / secrets never logged.
- [ ] Retention aligned with compliance policy.

## Dependencies

- [ ] New deps pinned; license checked.
- [ ] `npm audit` / `pip-audit` / equivalent clean or triaged.
- [ ] No runtime fetch of arbitrary code from the internet.

## Error handling + fail-safe

- [ ] Default is **deny** on auth/authz failures.
- [ ] Default is **fail-closed** for security-critical components
      (signature verification, license checks).
- [ ] Retries/fallbacks never downgrade security (e.g. never silently
      retry with weaker auth).

## Threat model sanity check

At least name the top two risks and their mitigations:

| Risk | Mitigation |
|---|---|
| Spoofed tenant access | Tenant ID from auth context only |
| Stolen session | Short JWT + rotating refresh + device binding |

## Before code review

- [ ] All boxes above are ticked, skipped with justification, or
      explicitly deferred with a follow-up ticket.
- [ ] The design's "Security" section reflects reality, not aspirations.
- [ ] Anyone reviewing can answer: *who can call this, what do they
      get, what do we log?*
