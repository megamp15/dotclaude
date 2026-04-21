# Authentication and authorization

## Terminology

- **Authentication (authn)** — "who are you?"
- **Authorization (authz)** — "what are you allowed to do?"
- **Session** — a continued claim of identity between requests.
- **Principal** — user, service account, or token subject.

## Password storage

### Algorithm

**First choice: Argon2id.** Memory-hard, designed for this purpose.

```python
from argon2 import PasswordHasher

ph = PasswordHasher(time_cost=3, memory_cost=64_000, parallelism=1)
hashed = ph.hash(password)
ph.verify(hashed, password)        # raises on mismatch
```

**Fallback: bcrypt with cost 12+** (for runtimes without Argon2
libraries).

**Never**: MD5, SHA1, SHA256-of-password, unsalted anything.

### Peppering

A secret key mixed in before hashing, stored separately from the
DB:

```python
mac = hmac.new(pepper_key, password.encode(), "sha256").hexdigest()
hashed = ph.hash(mac)
```

Defends against DB dump where attacker also doesn't have the pepper.
Doesn't replace a real hashing algorithm.

### Migrations

- When verifying, check parameter cost; if below current policy,
  **rehash and save** while you have the plaintext.
- Support multiple hash versions with a `$argon2id$v=19$...` style
  prefix (most libraries include this).

## Sessions vs. JWTs vs. opaque tokens

| Shape | Pros | Cons |
|---|---|---|
| **Server-side session** (cookie holds opaque ID; server looks up state) | Instant revocation; small cookie; no crypto mistakes | Server-state cost; sticky sessions or shared session store |
| **Opaque bearer token** (like session ID but for API) | Same as above, for APIs | Same as above |
| **Signed JWT** | Stateless; microservices can verify offline | Revocation requires extra infra; large; many footguns |

### Recommendation

- **Web apps**: server-side session, cookie-based. `HttpOnly`,
  `Secure`, `SameSite=Lax`. Short absolute + idle timeout; refresh
  by interaction.
- **APIs (same origin)**: same session cookie.
- **APIs (cross-origin / mobile)**: opaque bearer token from an
  IdP; rotate frequently. Or JWT with short (5–15 min) TTL +
  refresh token.
- **Service-to-service**: mTLS or short-lived JWT issued by a
  trusted signer.

### JWT done safely

Rules:

1. **Allowlist `alg`.** Explicit `["RS256"]` in verify. **Reject
   `none`.** Reject `HS256` if your key server uses RS256.
2. **Short TTL** — 15 min for access tokens; separate refresh
   tokens with rotation.
3. **Key rotation** — support multiple public keys via JWKS URI,
   rotate frequently.
4. **`aud` + `iss` + `exp` + `nbf`** — verify all four.
5. **Never put secrets in JWT claims.** They're base64, not
   encrypted.
6. **Don't use JWT as a session** in a monolith. Use a cookie
   session.

Use a library (`jose`, `python-jose`, `jsonwebtoken`). Hand-rolled
JWT parsing is a CVE magnet.

## OAuth / OIDC

- **Authorization Code + PKCE** for all public clients (browser,
  mobile, SPA). Drop implicit flow.
- **State** parameter — CSRF protection.
- **Nonce** (for OIDC) — replay protection.
- **Scopes** — least privilege; don't request `*` / `admin:*`.
- **Token endpoint** uses client credentials (or client assertion
  for confidential clients).
- **Redirect URI** — exact-match allowlist. No open redirects.
- **Use an off-the-shelf library** (NextAuth, Auth.js, Authlib,
  `ory/client-go`); don't implement OAuth 2.0 from scratch.

## Session cookie flags

```
Set-Cookie: session=abc; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=3600
```

- `HttpOnly` — JS can't read.
- `Secure` — HTTPS only.
- `SameSite=Lax` — prevents most CSRF. `Strict` if your flow
  doesn't involve cross-site links to authenticated areas.
  `SameSite=None; Secure` only for intentionally cross-site cookies
  (e.g., OAuth in iframe).
- `Path` — scope down if possible.
- `__Host-` prefix — adds constraints (forces `Secure`, forbids
  `Domain`).

## CSRF

With `SameSite=Lax` cookies, CSRF is mostly solved. Remaining cases:

- **Cross-site POSTs** initiated from your own domain (subdomain
  flank) — consider `SameSite=Strict` or token-based CSRF.
- **Legacy browsers** — add a synchronizer token pattern
  (double-submit cookie, or server-signed random token in form).

For APIs served to JS on your own origin:

- Require `Origin` header to match.
- Or add a `X-Requested-With` header custom; browsers block cross-
  origin custom headers without a CORS preflight.

## Rate limiting

At least three buckets:

- **Per-IP** — crude but stops mass abuse.
- **Per-user** — fair-use cap.
- **Per-endpoint** — expensive endpoints need tighter limits.

Ideal layer: **edge** (Cloudflare, AWS WAF, nginx `limit_req`). App
layer as a fallback. Return `429 Too Many Requests` with
`Retry-After`.

For login endpoints specifically:

- Exponential back-off per account (not just per IP — attackers
  rotate IPs).
- Lockout after N failures, unlock via email link or admin.
- Don't reveal "email not found" vs. "wrong password" at the
  endpoint; leak just "invalid credentials".

## Authorization models

### Role-Based Access Control (RBAC)

- Users belong to roles; roles have permissions.
- Works for org tools with clear role hierarchy (admin, editor,
  viewer).
- Falters once roles multiply into dozens of combinations.

### Relationship-Based Access Control (ReBAC)

- Permissions computed from relationships (user X is a member of
  org Y, which owns resource Z).
- Tools: Google Zanzibar-style (SpiceDB, OpenFGA, OSO Cloud, Auth
  Zed, Permit.io).
- Right choice for multi-tenant SaaS, document sharing,
  collaboration apps.

### Attribute-Based (ABAC)

- Policies over attributes (user.department == resource.department).
- Fine-grained but hard to debug.
- Tools: OPA (Rego), Cedar (AWS Verified Permissions).

### Recommendation

- **Start with RBAC** for simple apps.
- **Move to ReBAC** when sharing, collaboration, or hierarchy
  emerge.
- **Consider ABAC/Policy engines** for compliance-heavy domains.

## Authorization check location

Check authz **at the data access layer**, not just in middleware:

```python
# Bad — middleware check; easy to miss one path
@app.get("/docs/{doc_id}")
def read_doc(doc_id: str, user: User = Depends(require_auth)):
    return db.docs.get(doc_id)   # ← nothing checks ownership

# Good — per-resource check
def read_doc(doc_id: str, user: User = Depends(require_auth)):
    doc = db.docs.get_for_user(doc_id, user.id)   # raises if not allowed
    return doc
```

Even better: **scope every query by principal**. `WHERE tenant_id =
:tenant AND owner = :user`. The query layer enforces tenancy.

## Tenant isolation

For multi-tenant SaaS:

- **Shared DB + tenant column**: discipline; easy to forget a
  `WHERE tenant_id =`. Use PostgreSQL **Row-Level Security** to
  make it automatic.
- **DB-per-tenant**: better isolation, operational overhead.
- **Schema-per-tenant**: middle ground in Postgres; beware schema
  sprawl.

Row-Level Security example (Postgres):

```sql
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON documents
  USING (tenant_id = current_setting('app.tenant_id')::uuid);
```

At session start: `SET LOCAL app.tenant_id = '...';`. Queries
automatically scoped.

## Multi-factor authentication

- **TOTP** (RFC 6238) — default 6-digit, 30s period. Display a QR
  code for `otpauth://` URI.
- **WebAuthn / Passkeys** — gold standard; phishing-resistant.
- **SMS** — better than nothing; vulnerable to SIM swap. Avoid for
  privileged accounts.
- **Recovery codes** — generate once, stored hashed, one-time use.

Flow:

1. User registers second factor after login.
2. Prompt on subsequent logins.
3. Allow a "remember this device" with a bound cookie, capped at
   30 days.

## Accepting an API key

- Generated server-side (CSPRNG), displayed once, stored **hashed**.
- Prefixed with a key identifier so you can look it up (`pk_abc...`).
- Scope + expiry per key.
- Rate-limited.
- Revocable.

Checking:

```python
prefix = token[:8]
hashed = hashlib.sha256(token.encode()).hexdigest()
key = db.api_keys.get(prefix)
if key is None or not secrets.compare_digest(key.hashed, hashed):
    raise Unauthorized
```

`compare_digest` prevents timing attacks.

## Privilege escalation paths to inspect

- **Admin panel exposure.** Is there a route `/admin` that only
  checks authn, not "is this user admin"?
- **Horizontal escalation.** Can user A read user B's data by
  changing an ID?
- **Vertical escalation.** Can a normal user hit an admin
  endpoint? What about via mass-assignment (`role: "admin"` in a
  JSON body)?
- **Feature flags.** Do they check by user identity or a generic
  cookie?
- **Orgs / teams.** Can an invited guest edit settings?
- **Impersonation.** Is there an "admin can log in as user" path?
  Audit-log every such event.

## Logging

Always log:

- Login success / failure.
- Password reset requests.
- Authorization denials.
- Permission changes.
- Privileged actions (admin impersonation, data exports).

Never log:

- Passwords, API keys, tokens (even hashed — especially not as
  plaintext).
- Full PANs / SSNs.
- MFA codes.

Scrubber at log-write time, not just at aggregation.
