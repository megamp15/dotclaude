# guard mode

Secure-by-default guidance **at write time**. Applied proactively while
code is being authored, not as a separate audit pass. Activates when the
work touches trust boundaries, auth, crypto, secrets, or third-party
integrations.

> Distinct from `review` mode (diff-scoped) and `audit` mode (scoped
> feature/area). The mode-selection table is in the parent `SKILL.md`.

## When this mode is active

- Implementing an endpoint that accepts external input.
- Adding a new authn / authz flow.
- Storing anything that could be a credential, token, or PII.
- Introducing a crypto call (hashing, signing, encryption).
- Integrating a third-party API that issues credentials back to you.
- Writing any code that constructs shell commands, SQL, or HTML from
  variables.
- Reviewing a dependency for adoption.

## Sub-references (load on demand)

- [`input-and-output.md`](input-and-output.md) — trust boundaries, schema
  validation, parameterized queries, output encoding by context, SSRF
  defense, deserialization, file upload handling.
- [`authn-and-authz.md`](authn-and-authz.md) — password storage (argon2id,
  bcrypt), session vs. JWT vs. opaque tokens, OAuth/OIDC defaults,
  authorization checks at the right layer, tenant isolation patterns,
  rate limiting.
- [`crypto-and-secrets.md`](crypto-and-secrets.md) — "don't roll your own
  crypto", choosing libraries (libsodium, WebCrypto, `cryptography`),
  at-rest encryption keys, secret storage (Vault, AWS SM, sealed secrets),
  secret scanning, signing webhooks, TLS discipline.

## Workflow

1. **Identify the trust boundary.** What crosses from attacker-
   controllable to trusted? Every such crossing needs validation.
2. **Validate on input, encode on output.** Parse with a schema at the
   edge, re-encode when it leaves for a new context (HTML, SQL, shell,
   headers).
3. **Prefer parameterization / structured APIs** over string
   concatenation — SQL params, prepared statements, `subprocess` with a
   list, HTML templates with auto-escape.
4. **Fail closed.** When in doubt, deny. `401` > "guess it's fine".
5. **Least privilege.** Tokens scope-limited, DB users minimal, service
   accounts per function.
6. **Keep secrets out of source**, out of logs, out of error pages, off
   the command line. Rotate them on a schedule and on incidents.
7. **Update dependencies routinely.** Transitive vulnerabilities are the
   majority of real-world breaches.

## Defaults

| Concern | Default |
|---|---|
| Input validation | Schema (Zod / Valibot / Pydantic) at every entry point |
| SQL | Parameterized / prepared statements; never string-concat |
| Shell invocation | `subprocess.run(["cmd", arg])` with list args; never `shell=True` on user input |
| HTML output | Template with auto-escape (Jinja2, React, Svelte) |
| Password hashing | Argon2id (m=64MB, t=3, p=1) or bcrypt (cost 12+) |
| Session token | Opaque, HTTPS-only, `HttpOnly`, `SameSite=Lax`, short-TTL + refresh |
| JWT usage | Only for short-lived API auth; `alg` allowlist; no `none` algorithm |
| Crypto library | libsodium / NaCl wrappers; `cryptography` (Python); WebCrypto (browser) |
| Random | CSPRNG (`secrets`, `crypto.getRandomValues`) — never `Math.random` for secrets |
| TLS | 1.2+ everywhere; HSTS on public web; certificate pinning for mobile |
| CORS | Explicit allowlist of origins; `credentials: true` only when needed |
| CSP | Default-deny; allowlist script / style sources; no `unsafe-inline` |
| Rate limiting | Per-IP + per-user + per-endpoint buckets; fail at the edge |
| Secret storage | Vault / AWS SM / GCP SM / Azure KV; k8s external-secrets; never in repo |
| Secret detection | `gitleaks` / `trufflehog` in pre-commit + CI |
| Dependency scan | `npm audit --production`, `pip-audit`, `cargo audit`, `trivy` — in CI, fail on high |
| Container base image | Distroless, Chainguard, or minimal Alpine; pin by digest |
| Supply chain | SBOM generated per release; `cosign sign` images |
| Webhooks | HMAC signature with rotated key; constant-time compare |

## Guard-specific anti-patterns

- **Trusting the client.** Hidden fields, `disabled=true`, client-side
  validation — all gone once the attacker opens devtools.
- **String-formatting SQL or shell commands.** Parameterize.
- **Rolling your own crypto.** Use a vetted library. Period.
- **`alg: none` accepted in JWT verify.** Reject.
- **Authorization checks in middleware only.** Per-resource checks at the
  data layer too. Tenant isolation bugs hide here.
- **Sensitive data in logs.** Passwords, tokens, PII, payment info.
  Redact on log entry.
- **`.env` files in the repo.** Even example ones should be `.env.example`
  with **fake** values.
- **Swallowing stack traces but keeping them in production error
  responses.** Information leak.
- **Catch-all CORS (`Access-Control-Allow-Origin: *`) combined with
  credentials.** Combination is a vuln; browsers will block appropriately
  but your API shouldn't offer it.
- **Relying on obscurity** — "the endpoint URL is secret" isn't a security
  control.
- **Weak password policies** for admin accounts "because it's internal".
  Internal is the attacker's destination.
- **Unbounded file uploads** — size, type, content scanning, per-user
  quota all required.
- **Unsigned webhooks** — anyone who guesses the URL can post.

## Output format

For a secure code decision:

```
Trust boundary:     <which>
Untrusted input:    <what>
Asset protected:    <what>
Threat model:       <top 1-2 threats>

Controls:
  Validation:       <where + how>
  Encoding/output:  <where + how>
  AuthN / AuthZ:    <where + how>
  Logging:          <what's redacted>

Explicit non-controls (acknowledged):
  - <what this doesn't defend against>
```

For a library / dependency choice:

```
Package:            <name@version>
Maintenance:        <last release; open CVEs; # maintainers>
License:            <spdx>
Known CVEs:         <list>
Transitive surface: <count or noteworthy>
Verdict:            adopt | with pinning | don't adopt
Notes:              <audit findings, alternatives>
```

## The 10-second checklist (for every new endpoint)

- [ ] Authn required? Is the check enforced?
- [ ] Authz: can this user access *this specific resource*?
- [ ] Inputs validated with a schema?
- [ ] SQL / shell / eval parameterized?
- [ ] Output encoded for its context?
- [ ] Rate-limited?
- [ ] Logged (but not secrets)?
- [ ] Errors don't leak internals?
- [ ] Does this belong to a tenant? Is the tenant check present?
