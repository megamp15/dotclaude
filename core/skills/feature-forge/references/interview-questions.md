---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/feature-forge/references/interview-questions.md
ported-at: 2026-04-17
adapted: true
---

# Interview questions

Closed questions first (structured choice), open-ended second (free-form
elaboration). Structured choice reveals disagreement fastest; open-ended
fills in what the choices miss.

## PM hat — user value + business goals

| Area | Questions |
|---|---|
| Problem | What problem does this solve? Who experiences it? How often? |
| Users | Target users? Goals? Technical level? |
| Value | How will users benefit? Business value? ROI? |
| Scope | In scope? Explicitly out of scope? MVP vs. full? |
| Success | How will we measure success? Key metric? |
| Priority | Must-have / should-have / nice-to-have? |

### Example — "User export"

- Who needs to export data and why?
- What format (CSV, JSON, Excel, PDF)?
- How much data — 100 rows or 1M?
- Compliance (GDPR) or convenience?
- How often used?
- Deadline?

## Dev hat — technical feasibility + edge cases

| Area | Questions |
|---|---|
| Integration | What systems does this touch? APIs, DBs, services? |
| Security | Auth required? Data sensitivity (PII, PCI)? |
| Performance | Expected load? Response time? Async acceptable? |
| Edge cases | What if X fails? Empty states? Limits? |
| Data | What's stored? Retention? Backup needs? |
| Dependencies | External services? Rate limits? Costs? |

### Example — "User export"

- Which fields? Any sensitive (passwords, tokens)?
- Max export size? Streaming or background job?
- Include soft-deleted records?
- What if the export fails midway?
- File retention — how long to keep generated files?
- Progress indicator for large exports?

## Use AskUserQuestions (structured choice) when the answer is finite

### When to use

| Question shape | Example | Option style |
|---|---|---|
| Priority | "Is this must-have or nice-to-have?" | Single-select: Must / Should / Nice |
| Format | "Which export formats?" | Multi-select: CSV / JSON / Excel / PDF |
| Scope | "MVP or full or phased?" | Single-select: MVP / Full / Phased |
| Yes/no with nuance | "Auth required?" | Single-select: Public / Authenticated / Role-based |
| Error handling | "How to handle failures?" | Single-select: Retry / Fail fast / Queue / Notify |

### When not to use

- "Describe the user journey in your own words."
- "What problem does this solve?"
- "Walk me through the workflow."

Open-ended questions produce context that structured choice can't.

## Interview flow (recommended)

### Phase 1: Discovery (mostly open-ended → close down)

1. Open: "Tell me about this feature in your own words."
2. Open: "What problem are we solving?"
3. Close: target users (single-select from identified personas).
4. Close: usage frequency (Daily / Weekly / Monthly / Rarely).
5. Close: priority (Must / Should / Nice).

### Phase 2: Details (close → open)

1. Close: scope (MVP / Full / Phased).
2. Close: key capabilities (multi-select from discovered list).
3. Open: "Walk me through the user journey."

### Phase 3: Edge cases (close → open)

1. Close: error handling approach (Retry / Fail fast / Queue / Notify).
2. Close: data limits (multi-select thresholds).
3. Open: "What happens when X fails?"

### Phase 4: Validation

1. Present spec summary.
2. Close: "Does this capture your requirements?" (Yes / Needs changes / Major gaps).
3. Close per-requirement priority if there are disputes.

## Security + compliance quick bank (always ask)

- Who can call this? (public, auth, role-gated, MFA-gated)
- What data is read/written? (PII, PCI, PHI, internal, public)
- What's the retention rule for logs, exports, artifacts?
- Is there a compliance framework in scope (GDPR, HIPAA, PCI-DSS, SOC 2)?
- Who else needs to sign off before launch? (legal, security, privacy)

## Multi-agent pre-discovery (for cross-cutting features)

When a feature spans multiple domains, front-load technical context with
parallel subagent work **before** the interview:

```
Before interview, launch in parallel:
- architecture-designer: assess system impact
- security-reviewer / audit: identify auth and data concerns
- explore agent: search the codebase for similar patterns

Collect findings → use them to sharpen interview questions
```

This makes the interview about *decisions*, not *discovery*.

## Quick reference

| Phase | Focus | Tool |
|---|---|---|
| Pre-discovery | Technical context | Subagents / grep |
| Discovery | Problem, users, value | Open → close |
| Details | Journey, scope, constraints | Close → open |
| Edge cases | Failures, limits, security | Close → open |
| Validation | Summary, gaps, priorities | Close |
