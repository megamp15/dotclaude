---
name: security
description: Security work in three modes — guard (write-time defensive coding), review (diff/PR security pass), and audit (scoped feature/area review). The skill auto-detects mode from context (writing new code → guard; diff/PR present → review; "audit X before release" → audit) and routes to the matching reference. Subagent form lives at core/agents/security-reviewer.md and is invoked by pr-review and dotclaude-parallel.
source: core
triggers: /security, security review, security audit, secure coding, OWASP, SQLi, XSS, CSRF, SSRF, JWT, OAuth, password hashing, argon2, bcrypt, secrets, TLS, CORS, CSP, input validation, output encoding, parameterized query, threat model, audit before release, review my diff for vulnerabilities, secure-by-default
ported-from: https://github.com/Jeffallan/claude-skills (security-reviewer, secure-code-guardian)
ported-at: 2026-04-17
adapted: true
---

# security

One skill, three modes. Pick the mode by what you're doing, not by what
sounds important. Guess wrong and the output is shaped wrong: a write-time
defensive checklist isn't a PR review report, and a PR review isn't a
feature audit.

> **See also:**
>
> - `core/agents/security-reviewer.md` — subagent form. Invoke as a
>   delegate inside a larger review (e.g., the `pr-review` orchestrator
>   or `dotclaude-parallel` PR-review template).
> - `core/rules/security.md` — baseline always-on rules that apply
>   regardless of mode.

## Mode selection

| Signal in the prompt / context | Mode |
|---|---|
| User is *writing* new code touching auth/crypto/I/O/secrets/templates | **guard** |
| There's a diff, PR, or staged changeset on the table | **review** |
| User says "audit X before release", "review the auth feature", scoped review of a sensitive area | **audit** |

If two signals fit, ask. Don't pick by vibes — the report shape differs.

The three modes share the same severity scale (below) and the same
exploitability-first ground rules. They differ in *scope* and *output*.

## Ground rules (all modes)

- **Exploitability first.** A finding you can describe an attacker's steps
  for is real. A finding you can't is noise.
- **Evidence.** File + line + the specific input that triggers the bad path.
- **No theater.** Don't pad with "consider using HTTPS" if the project
  already uses HTTPS. Don't recommend a WAF in lieu of pointing at the
  vulnerability.
- **Resist severity inflation.** Three real "high"s beat ten theoretical
  ones. A report with seven highs where two are real and five are
  theoretical buries the two.
- **Clean-bill the categories you checked.** Listing only findings hides
  whether you actually looked.

## Severity (all modes use this scale)

- **Critical** — RCE, auth bypass, full data exfil, privilege escalation
  with no prerequisites, secret disclosure in prod.
- **High** — data exfil requiring weak preconditions, stored XSS, SQLi,
  IDOR on sensitive data, CSRF on state-changing operations, broken crypto
  on sensitive data.
- **Medium** — reflected XSS needing click, missing rate limit on abusive
  endpoint, sensitive info in error responses, weak crypto for non-critical
  data.
- **Low** — minor information disclosure, missing hardening headers,
  verbose errors to users.
- **Info** — hygiene notes, not exploitable today but worth fixing.

## The modes

### guard — write-time defensive coding

Active *while code is being authored*, not after. Use when implementing
endpoints, auth flows, crypto calls, secret handling, or any code that
constructs SQL/shell/HTML from variables. The skill prescribes
secure-by-default patterns and produces a controls-checklist for the change.

**Load:** [`references/guard.md`](references/guard.md) for the full
defaults table, controls, anti-patterns, and the 10-second checklist for
new endpoints. Sub-references:

- [`references/input-and-output.md`](references/input-and-output.md) — trust
  boundaries, schemas, parameterization, encoding, SSRF, deserialization,
  uploads.
- [`references/authn-and-authz.md`](references/authn-and-authz.md) —
  password storage, session vs. JWT, OAuth/OIDC, tenant isolation,
  rate limiting.
- [`references/crypto-and-secrets.md`](references/crypto-and-secrets.md) —
  library choice, at-rest encryption, secret storage, signing webhooks,
  TLS discipline.

### review — diff-scoped security review

Use when a PR or uncommitted diff is on the table. **Read the diff first.**
Don't tour the repo. Run the ten-item diff-scoped checklist, expand only
where the diff touches a trust boundary / auth / crypto / I/O. Output as a
ranked findings report with a clean-bill section.

**Load:** [`references/review.md`](references/review.md) for the workflow,
ten-item checklist, output format, and `pr-review` integration.

### audit — scoped feature / area audit

Use when the user asks for a security review of a specific component or
surface (auth, payment, file upload, multi-tenant isolation) — narrower
than "the whole app", wider than a single diff. Establishes scope, walks
the OWASP categories that apply, produces ranked findings.

**Load:** [`references/audit.md`](references/audit.md) for the workflow,
attack-surface enumeration, and report format. Backbone:
[`references/owasp-checklist.md`](references/owasp-checklist.md).

## Anti-patterns (all modes)

- Running an audit on an entire 100k-LOC repo with no scope. Result is
  shallow noise.
- Marking everything "High" so the report looks important.
- Recommending architecture changes ("use a WAF") in place of pointing at
  a concrete vulnerability.
- Flagging missing response headers when the issue is a missing auth check
  three files over.
- Listing only findings without "categories checked" — makes reviewers
  doubt coverage.
- Expanding scope silently. If the user asked about one PR, don't audit
  the rest of the repo. Offer a separate `audit` mode for adjacent areas.

## Integration with pr-review and dotclaude-parallel

`pr-review` (sequential) and `dotclaude-parallel` (Agent Teams) both
delegate to `core/agents/security-reviewer.md` for the security lens of a
larger review. The skill form (this file) is for direct user invocation;
the agent form is for orchestrator-driven delegation. Same severity scale,
same finding format — just invoked differently.
