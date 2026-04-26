# audit mode

Scoped feature / area security audit. Wider than a diff, narrower than the
whole app. Use when the user asks for a security review of a specific
component or surface — auth, payment, file upload, user content,
multi-tenant isolation — usually before a release or when the area is
known-sensitive.

> Distinct from `review` mode (diff-scoped) and `guard` mode (write-time).
> The mode-selection table is in the parent `SKILL.md`.

## How this is different from `code-reviewer`

`code-reviewer` looks at correctness, maintainability, and real bugs
broadly. `audit` mode specifically hunts exploitable issues and ignores
everything else. Different lens, different findings.

If the user wants a pre-release review, run both.

## Workflow

### 1. Establish scope

Ask, if not given:

- Which component / surface? (endpoint, feature, directory, whole app)
- What's the trust boundary? Who's the untrusted actor? (anonymous user,
  authenticated user, admin, other tenant, dependency)
- What's the asset? (user data, money, access to infra, other tenants' data)

Without these three, the audit is vibes.

### 2. Read the attack surface

Enumerate entry points in scope:

- HTTP routes + methods. Auth requirements per route.
- CLI flags / env vars that accept untrusted input.
- File upload paths.
- Message / queue consumers.
- Deserialization surfaces.
- Any `eval`, `exec`, template compile, shell invocation with interpolated
  input.

List them before digging. A finding on a route you didn't realize existed
is the most common missed finding.

### 3. Walk each category

Use [`owasp-checklist.md`](owasp-checklist.md) as the backbone. For each
item, **either**:

- Point to the defense in the code (route requires auth, input validated,
  output escaped) — this is the "clean bill" for that category.
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

### 5. Summary

At the top of the final report:

- Scope audited (routes / files / feature)
- Counts per severity
- Top 3 items to fix first
- What was explicitly out of scope

## Audit-specific anti-patterns

- Running this on an entire 100k-LOC repo with no scope. You'll produce
  shallow nonsense.
- "Consider using a WAF." — architectural recommendations without a
  specific vulnerability to justify them.
- Flagging missing response headers when the real issue is a missing auth
  check three files over.

## When to escalate

- If during scoping the user can't name an asset and a threat actor, the
  audit will be shapeless. Push back: "what's the worst thing an attacker
  could do here?" If still unclear, narrow scope or convert to `review`
  mode against a specific diff.
- If the audit surfaces architectural problems that no single fix
  addresses — e.g., "auth is checked at the wrong layer everywhere" — flag
  it as a finding *and* recommend a follow-on architecture-designer
  engagement. Don't try to fix architecture inside an audit report.
