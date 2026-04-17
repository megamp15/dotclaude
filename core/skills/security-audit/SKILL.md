---
name: security-audit
description: Run a focused security review against a scoped area of the codebase — auth, input handling, secrets, injection, access control
source: core
---

# Security audit

Use when: user asks for a security review, an audit before release, or a
scoped review of a security-sensitive feature (auth, payment, file upload,
user content, multi-tenant isolation).

Not for: drive-by nitpicks. Not for DevSecOps posture at an org level.
That's a different conversation.

## How this is different from `code-reviewer`

`code-reviewer` looks at correctness, maintainability, and real bugs
broadly. `security-audit` specifically hunts exploitable issues and ignores
everything else. Different lens, different findings.

If the user wants a pre-release review, run both.

## Ground rules

- **Exploitability first.** A finding I can describe an attacker's steps for is real. A finding I can't is noise.
- **Evidence.** File + line + the specific input that triggers the bad path.
- **Scope bound.** If the user hasn't said what to audit, ask. "Everything" leads to shallow review everywhere.
- **No theater.** Don't pad the report with "consider using HTTPS" if the project already uses HTTPS.

## Workflow

### 1. Establish scope

Ask, if not given:

- Which component/surface? (endpoint, feature, directory, whole app)
- What's the trust boundary? Who's the untrusted actor? (anonymous user, authenticated user, admin, other tenant, dependency)
- What's the asset? (user data, money, access to infra, other tenants' data)

Without these three, the audit is vibes.

### 2. Read the attack surface

Enumerate entry points in scope:

- HTTP routes + methods. Auth requirements per route.
- CLI flags / env vars that accept untrusted input.
- File upload paths.
- Message/queue consumers.
- Deserialization surfaces.
- Any `eval`, `exec`, template compile, shell invocation with interpolated input.

List them before digging. A finding on a route you didn't realize existed is the most common missed finding.

### 3. Walk each category

Use `references/owasp-checklist.md` as the backbone. For each item, **either**:

- Point to the defense in the code (route requires auth, input validated, output escaped) — this is worth noting briefly; it's the "clean bill" for that category.
- Point to the gap with a concrete exploit sketch.

Skip categories that don't apply (no file upload → no file-upload section).

### 4. Write findings

Format (one per issue):

```
### [SEV] short title

**Location:** `path/to/file.ext:42`
**Surface:** e.g. `POST /api/comments`, auth = none
**Issue:** one-sentence description
**Exploit:** minimal attacker steps, ideally with a sample payload
**Impact:** what an attacker gets (data, access, downtime)
**Fix:** what to change, concretely. Mention alternatives if relevant.
```

### Severity (be honest)

- **Critical** — remote code execution, auth bypass, full data exfil, privilege escalation with no prerequisites.
- **High** — data exfil requiring weak preconditions, stored XSS, SQLi, auth bypass requiring a specific user interaction.
- **Medium** — CSRF on state-changing endpoint, reflected XSS, sensitive info in logs, rate-limit bypass enabling abuse.
- **Low** — minor information disclosure, missing hardening headers, verbose errors to users.
- **Info** — hygiene notes, not exploitable today but worth fixing.

Resist inflation. A review with seven "High" findings where two are real and five are theoretical buries the two.

### 5. Summary

At the top of the final report:

- Scope audited (routes / files / feature)
- Counts per severity
- Top 3 items to fix first
- What was explicitly out of scope

## References

- `references/owasp-checklist.md` — category-by-category checklist
- `core/rules/security.md` — universal baseline rules
- `core/agents/security-reviewer.md` — use for subagent-style delegation inside a larger review

## Anti-patterns

- Running this on an entire 100k-LOC repo with no scope. You'll produce shallow nonsense.
- Marking everything "High" so the report looks important.
- "Consider using a WAF." — architectural recommendations without a specific vulnerability to justify them are out of scope for this skill.
- Flagging missing response headers when the issue is a missing auth check three files over.
