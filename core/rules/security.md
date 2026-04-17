---
name: security
description: Universal security guardrails applied regardless of language or framework
source: core
alwaysApply: true
---

# Security

Language-agnostic defense rules. Framework-specific guidance (CSRF tokens,
ORM parametrization syntax) lives in stack rules.

## Secrets

- **Never commit secrets** — API keys, tokens, passwords, private keys, connection strings with credentials.
- Read secrets from env vars, secret managers, or encrypted config — never from source files.
- If a secret was accidentally committed: rotate immediately, then scrub history. History scrub alone is not enough.
- `.env` files are for local dev. `.env.example` is committed with placeholder values; `.env` is gitignored.

## Input validation

- Validate at every trust boundary — not once, not deep in the stack. Boundaries: HTTP request, queue message, file parse, CLI arg, DB row you didn't write.
- Allowlist, not denylist. Specify what's valid; reject everything else.
- Validate type, range, length, encoding, and format — all four matter.
- Reject before parsing when possible (content-length limits, MIME checks).

## Injection

- **SQL:** parametrized queries or ORM-bound values only. Never string-concatenate user input into SQL.
- **Shell:** never pass user input to a shell. Use `exec`-style APIs with arg arrays.
- **HTML/template:** context-aware escaping. Raw HTML from user input is a trust decision — make it explicit, never accidental.
- **Path:** normalize and verify paths stay inside an allowed root. `..` segments are a red flag.
- **Deserialization:** never deserialize untrusted data with pickle/YAML load/unsafe JSON parsers.

## Auth & sessions

- Use established libraries for hashing passwords (bcrypt/scrypt/argon2). Never roll your own.
- Session tokens: cryptographic random, expire, rotate on privilege change, invalidate on logout.
- Authorization happens at every endpoint — authentication once is not enough. "Logged in" ≠ "allowed".
- Principle of least privilege: roles grant the narrowest scope that works.

## Transport & storage

- TLS everywhere. No `verify=False`, no self-signed certs in production, no `rejectUnauthorized: false`.
- Encrypt sensitive data at rest (PII, credentials, health records). Know your regulatory scope.
- Log access to sensitive data; never log the data itself.

## Logs

- Never log secrets, tokens, auth headers, session IDs, full credit card numbers, or passwords — even at DEBUG.
- Redact before logging: `api_key=***`. If the logger config doesn't redact, the call site must.
- Log error context (request ID, user ID) but not PII in plaintext.

## Dependencies

- Audit dependencies on every add (`npm audit`, `pip-audit`, `cargo audit`, etc.).
- Pin direct dependencies; resolve transitive via lockfile.
- Know what each dependency does before adding it. `left-pad` events are real.
- Remove unused dependencies — they're still attack surface.

## Things to never do

- `eval`, `exec`, `Function(...)` on user input.
- `innerHTML = userInput` (or equivalents).
- Regex-parse shell commands, URLs, SQL, or HTML.
- Cryptographic primitives you built yourself.
- `chmod 777`, `CORS: *` on authenticated endpoints, `Access-Control-Allow-Credentials: true` with `*` origin.
- Disable security features "just for this test" and forget to re-enable.

## When unsure

Ask: "if an attacker controlled this value, what's the worst they could do?" If the answer is unacceptable, add validation, escaping, or a constraint.
