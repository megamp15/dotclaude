---
name: security-reviewer
description: Diff-scoped security review — fast OWASP-aligned pass on a PR/diff with exploit-focused findings. Complements `core/skills/security-audit` (scoped feature/area audit) and `core/skills/secure-code-guardian` (write-time defensive coding). Skill form of `core/agents/security-reviewer`.
source: core
triggers: /security-reviewer, security review, PR security review, review my diff for vulnerabilities, OWASP review, secure the PR
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/security-reviewer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# security-reviewer

**Diff-scoped** security review. Use when you have a PR / changeset
and want a targeted, exploit-focused pass — not a full-feature audit.

> **See also:**
>
> - `core/agents/security-reviewer.md` — subagent form; invoke as a
>   delegate inside a larger review (e.g., the `pr-review` orchestrator).
> - `core/skills/security-audit/` — scoped feature/area audit (wider
>   than a diff; narrower than "the whole app").
> - `core/skills/secure-code-guardian/` — write-time defensive coding.
> - `core/rules/security.md` — baseline always-on rules.

## When to use this skill

- Reviewing a pull request or an uncommitted diff before it ships.
- The change touches auth, input handling, crypto, deserialization,
  external I/O, or anything containing user data.
- You want an exploit-focused pass, not maintainability feedback.

## When *not* to use this skill

- **Whole-app audit** — use `security-audit` with a narrower scope,
  or split into multiple passes.
- **Code quality / maintainability** — use `pr-review` or
  `code-reviewer`.
- **Ongoing posture / compliance** — that's an org-level workflow,
  not a skill.

## Core workflow

1. **Read the diff first.** Don't explore the whole codebase unless
   the diff references something you need to understand.
2. **Classify every hunk.** Each change falls into one of:
   - *Touches a trust boundary* → inspect deeply.
   - *Touches auth, crypto, or secret handling* → inspect deeply.
   - *Touches I/O or external services* → inspect for SSRF / injection.
   - *Pure refactor / internal* → skim, move on.
3. **Enumerate entry points introduced or modified.** New route?
   New queue consumer? New CLI flag? New webhook?
4. **Walk the OWASP checklist** (see agent at
   `core/agents/security-reviewer.md`), but only items the diff
   actually exercises.
5. **For each finding**, include the exploit sketch. No exploit
   sketch → not a finding.
6. **Rank and summarize.** Top 3 items to fix first.

## The ten-item diff-scoped checklist

For every diff, verify:

- [ ] **Authn** — new protected route has the auth decorator /
      middleware.
- [ ] **Authz** — new protected route checks the resource belongs
      to the user / tenant.
- [ ] **Input validation** — new params go through a schema
      (Zod / Pydantic).
- [ ] **SQL** — no string concatenation of user input; all params
      bound.
- [ ] **Shell / subprocess** — argv form, not `shell=True` on user
      input.
- [ ] **HTML / template output** — auto-escape on; no raw HTML
      injection.
- [ ] **Secrets** — no new hardcoded values; no `.env` in repo; no
      tokens in logs.
- [ ] **Crypto** — existing vetted library; no hand-rolled; no
      insecure algorithms.
- [ ] **CORS / CSP / cookies** — if headers changed, still tight?
- [ ] **Dependency adds** — CVE-clean; actively maintained;
      transitive surface acceptable.

## Output format

```
# Security review — <PR / diff>

## Summary
- Overall risk:    critical | high | medium | low | clean
- New surfaces:    <routes/consumers added>
- Findings:        crit=N  high=N  med=N  low=N
- Top 3 fixes:
    1. <severity> <file:line> — <short>
    2. ...
    3. ...

## Findings

### [critical] path/to/file.py:42 — <short title>
**Attack:**       <concrete steps>
**Impact:**       <what attacker gets>
**Likelihood:**   <high / medium / low; reachability, prereqs>
**Fix:**          <smallest closing change>

### [high] ...
### [medium] ...
### [low] ...

## Clean-bill categories

- <Category you checked and found OK, one line each. Keeps the
  report honest and shows coverage.>

## Out of scope

- <What this review didn't cover. E.g., "existing auth flow
  unchanged; not re-audited.">
```

## Severity scale (be honest)

- **critical** — RCE, auth bypass, SQLi with data access, admin
  privilege escalation, secret disclosure in prod.
- **high** — stored XSS, IDOR on sensitive data, CSRF on
  state-changing operations, broken crypto on sensitive data.
- **medium** — reflected XSS needing click, missing rate limit on
  abusive endpoint, weak crypto for non-critical data, sensitive
  info in error responses.
- **low** — missing security headers, minor info disclosure, dev-
  only CVEs, hygiene findings.
- **info** — not exploitable today but worth noting.

Resist inflation. Three real "high"s beat ten theoretical ones.

## Anti-patterns

- **Expanding scope silently.** If the user asked about one PR,
  don't tour the repo looking for issues. Offer a separate
  `security-audit` for adjacent areas.
- **Theoretical findings.** Timing-attack mentions with no
  reachable sink = noise.
- **Recommending architecture changes** ("use a WAF") in place of
  pointing at a concrete vulnerability.
- **Security theater headers** — finding only "missing
  `X-Content-Type-Options`" when the diff adds an SQLi-vulnerable
  endpoint.
- **No clean-bill.** Listing only findings without "categories
  checked" makes reviewers doubt coverage.

## Integration with `pr-review`

`pr-review` orchestrates multi-lens reviews. When it invokes
`security-reviewer`, it passes the diff summary; this skill /
agent returns findings in the format above; `pr-review` aggregates
with the `code-reviewer` and `performance-reviewer` outputs.

To run the subagent directly: see
`core/agents/security-reviewer.md`.
