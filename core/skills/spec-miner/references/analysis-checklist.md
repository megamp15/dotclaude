---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/spec-miner/references/analysis-checklist.md
ported-at: 2026-04-17
adapted: true
---

# Analysis checklist

Run through this before writing the spec. If more than a couple items are
"no", keep exploring.

## Coverage

- [ ] All manifests read (one per language/runtime).
- [ ] Every top-level module has a 1-line purpose.
- [ ] Every entry point identified (HTTP, CLI, queue, cron, webhook, gRPC).
- [ ] At least one critical entry point traced end-to-end (handler →
      domain → data → response → side effects).
- [ ] All data stores and external services listed.
- [ ] Auth + authorization model described (authn mechanism, authz model).
- [ ] All config / env vars discovered and categorized (required,
      optional, feature flag, secret).

## Behavior

- [ ] Every FR written in EARS.
- [ ] Every FR has a code citation.
- [ ] Each FR is labeled **observed** or **inferred**.
- [ ] Error paths covered (401, 403, 404, 409, 422, 5xx) — not just happy path.
- [ ] Side effects documented (events, cache, audit log, emails, webhooks).
- [ ] Feature flags / optional capabilities captured in EARS "optional" form.

## Non-functional

- [ ] Known latency / throughput numbers or honest "not measured".
- [ ] Availability posture (replicas, HA, failover).
- [ ] Rate limiting (present or absent).
- [ ] Logging format and key fields.
- [ ] Metrics / tracing / error tracking (what is emitted, what is not).
- [ ] Security posture (hashing, encryption, secrets handling, CORS,
      headers).

## Data

- [ ] Entities + fields + key constraints documented.
- [ ] Soft-delete and audit columns noted.
- [ ] Relationships + important indexes noted.
- [ ] Retention policies (if any).

## Tests + debt

- [ ] Test frameworks + coverage shape described.
- [ ] Significant `TODO`/`FIXME`/`HACK` markers surfaced.
- [ ] Deprecated code / dead paths flagged.

## Open questions

- [ ] All uncertainties surfaced in the "Open questions" section.
- [ ] Each open question tagged with impact (security, correctness,
      performance, compliance).
- [ ] Each open question has an owner or a "needs owner" tag.

## Output quality

- [ ] Spec opens with an executive summary a new owner can read in 60 s.
- [ ] Every FR is testable by someone who reads only the spec.
- [ ] No behavior claim without evidence.
- [ ] Inferences are labeled, not hidden.
- [ ] Recommendations section is actionable (not "improve performance").

## Red flags that mean stop and re-explore

- You can't list the entry points confidently.
- You haven't touched a single error path.
- Every FR cites the same two files.
- You found code you don't understand and skipped it.
- The "Uncertainties" section is empty (this is almost never correct).
