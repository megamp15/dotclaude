# review mode

**Diff-scoped** security review. Use when you have a PR / changeset and
want a targeted, exploit-focused pass — not a full-feature audit.

> Distinct from `audit` mode (scoped feature/area review) and `guard` mode
> (write-time defensive coding). The mode-selection table is in the parent
> `SKILL.md`.

## When to use this mode

- Reviewing a pull request or an uncommitted diff before it ships.
- The change touches auth, input handling, crypto, deserialization,
  external I/O, or anything containing user data.
- You want an exploit-focused pass, not maintainability feedback.

## When NOT to use this mode

- **Whole-app audit** — use `audit` mode with a narrower scope, or split
  into multiple passes.
- **Code quality / maintainability** — use `pr-review` or `code-reviewer`.
- **Ongoing posture / compliance** — that's an org-level workflow, not a
  skill.

## Workflow

1. **Read the diff first.** Don't explore the whole codebase unless the
   diff references something you need to understand.
2. **Classify every hunk.** Each change falls into one of:
   - *Touches a trust boundary* → inspect deeply.
   - *Touches auth, crypto, or secret handling* → inspect deeply.
   - *Touches I/O or external services* → inspect for SSRF / injection.
   - *Pure refactor / internal* → skim, move on.
3. **Enumerate entry points introduced or modified.** New route? New
   queue consumer? New CLI flag? New webhook?
4. **Walk the OWASP checklist** ([`owasp-checklist.md`](owasp-checklist.md)),
   but only items the diff actually exercises.
5. **For each finding**, include the exploit sketch. No exploit sketch →
   not a finding.
6. **Rank and summarize.** Top 3 items to fix first.

## The ten-item diff-scoped checklist

For every diff, verify:

- [ ] **Authn** — new protected route has the auth decorator / middleware.
- [ ] **Authz** — new protected route checks the resource belongs to the
      user / tenant.
- [ ] **Input validation** — new params go through a schema (Zod /
      Pydantic).
- [ ] **SQL** — no string concatenation of user input; all params bound.
- [ ] **Shell / subprocess** — argv form, not `shell=True` on user input.
- [ ] **HTML / template output** — auto-escape on; no raw HTML injection.
- [ ] **Secrets** — no new hardcoded values; no `.env` in repo; no tokens
      in logs.
- [ ] **Crypto** — existing vetted library; no hand-rolled; no insecure
      algorithms.
- [ ] **CORS / CSP / cookies** — if headers changed, still tight?
- [ ] **Dependency adds** — CVE-clean; actively maintained; transitive
      surface acceptable.

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

- <Category you checked and found OK, one line each. Keeps the report
  honest and shows coverage.>

## Out of scope

- <What this review didn't cover. E.g., "existing auth flow unchanged;
  not re-audited.">
```

## Review-specific anti-patterns

- **Expanding scope silently.** If the user asked about one PR, don't tour
  the repo looking for issues. Offer a separate `audit` for adjacent areas.
- **Theoretical findings.** Timing-attack mentions with no reachable sink
  = noise.
- **Security theater headers** — flagging only "missing
  `X-Content-Type-Options`" when the diff adds an SQLi-vulnerable endpoint.
- **No clean-bill.** Listing only findings without "categories checked"
  makes reviewers doubt coverage.

## Integration with pr-review and dotclaude-parallel

`pr-review` (sequential orchestrator) and `dotclaude-parallel` (Agent
Teams swarm) both delegate the security lens to
`core/agents/security-reviewer.md`. The agent uses the same workflow and
output format as this mode — the skill form is for direct user invocation,
the agent form is for orchestrator-driven delegation.

To run the subagent directly, see `core/agents/security-reviewer.md`.
