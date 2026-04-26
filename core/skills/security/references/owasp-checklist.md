---
source: core
---

# OWASP-aligned checklist

Not an exhaustive OWASP mapping — a practical list of what to actually
look for, reading code. Skip categories that don't apply.

## A01 — Broken access control

- Every route: who can call it? Check for the auth middleware. Missing is a finding.
- Every object access: is the caller allowed to see *this* object? IDs in URLs must be authorized against the caller, not just "user is logged in."
- Force-browse test: if `GET /users/42` works for user 42, does it work for user 43?
- Horizontal vs vertical: user → other user's data, and user → admin functions.
- Multi-tenant: tenant A must not read/write tenant B. Check every query filter.
- Admin functions behind role check on the **server** — hidden UI does not count.
- Default-deny: is the default "allow unless denied"? If so, flag it.

## A02 — Cryptographic failures

- Secrets in source, in logs, in error messages, in URLs. Any hit is a finding.
- Hard-coded keys, passwords, tokens. Even "test" ones in committed config.
- Weak hashing for passwords: MD5, SHA1, SHA256-plain. Must be bcrypt/argon2/scrypt with a cost factor.
- Weak ciphers (DES, RC4). Static IVs. ECB mode.
- TLS misconfig: allowing HTTP fallback where HTTPS is assumed.
- Tokens: signed? Algorithm pinned? Expiry enforced? Rotation possible?

## A03 — Injection

- **SQL:** every query. String concatenation / f-strings with user input = SQLi. Parameterize or ORM.
- **Command:** any `subprocess`, `exec`, `system`, `Runtime.exec` with interpolated input. Even "trusted" input.
- **LDAP / NoSQL / XPath** — same principle, different target.
- **SSTI** (server-side template injection): user input passed into template *compilation* (not just rendering).
- **HTTP header injection** via CRLF in header values.
- **Log injection** — newlines in logged user input.

## A04 — Insecure design

- Hard to spot at code-review level; usually belongs in architect review. But flag when obvious:
  - Security-sensitive logic relying on client-side checks.
  - No rate limiting on endpoints that allow automation-for-profit (signup, password reset, gift code redemption).
  - Password reset that doesn't invalidate sessions.

## A05 — Security misconfiguration

- Debug mode in production. Verbose errors to users.
- Default credentials anywhere.
- Dependency version with known CVE (cross-check).
- CORS `*` with credentials.
- Missing security headers where they meaningfully help: `Content-Security-Policy`, `Strict-Transport-Security`, `X-Content-Type-Options`.
- Open S3 buckets / open blob containers / publicly listable directories.

## A06 — Vulnerable components

- Locked versions. Recent audit run. Known high/critical in direct or transitive.
- Abandoned deps (no commits, no maintainer).
- Packages installed from non-standard sources without pin to commit.

## A07 — Authentication failures

- Password policy sanity. No "max length 8" absurdity.
- Rate limiting on login, password reset, 2FA code submission.
- Session fixation: session id rotates on privilege change (login, logout, password change).
- Logout invalidates server-side session, not just clears client cookie.
- Remember-me tokens are rotating and revocable.
- No secrets in URLs (password reset codes belong in request body or short-lived token).

## A08 — Software & data integrity failures

- Unsigned updates / plugins.
- Deserialization of untrusted data (`pickle`, Java serialization, PHP unserialize). Every instance is a finding unless proven safe.
- CI/CD pipeline: who can push what to production? Secrets scoped correctly?

## A09 — Logging & monitoring failures

- Auth failures logged? Privileged actions logged? Rate-limit-trigger logged?
- Are logs scrubbed of PII and secrets? (Hooks scan source; tests should too.)
- Can you reconstruct "who did what when" for an incident?

## A10 — SSRF

- Any outbound HTTP where the URL comes from user input.
- Image fetchers, webhook registration, URL-preview, file import.
- Defense: allowlist, resolve + block internal ranges (169.254, 10.*, 172.16-31.*, 192.168.*, link-local), no redirects to blocked ranges.

## Mobile / API / web-specific additions

### Web

- XSS: user input rendered as HTML/JS without escaping.
- CSRF: state-changing endpoints over cookies without CSRF token or SameSite=Strict.
- Clickjacking: missing frame-ancestors / X-Frame-Options.
- File upload: content-type validation server-side, not just extension; serve uploads from a different origin or with `Content-Disposition: attachment`.

### API

- Auth required on every non-public route.
- Object IDs authorized per-request (A01).
- Rate limiting per principal, not per IP.
- Pagination bounded.
- Error messages don't leak implementation detail (stack traces, ORM queries).

### File operations

- Path traversal: user input joined into a path without canonicalization + containment check.
- Zip-slip: entries in uploaded archives with `../` in names.
- Symlink attacks on extract paths.

## When to stop looking

You've read every in-scope entry point, checked each category that
applies, and written findings with exploit sketches. Adding hypothetical
categories doesn't improve the audit; it dilutes it.
