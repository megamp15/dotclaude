---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/architecture-designer/references/nfr-checklist.md
ported-at: 2026-04-17
adapted: true
---

# Non-functional requirements checklist

A design without NFRs is guessing. Before proposing an architecture, fill in
this checklist. If the stakeholder can't answer, your first deliverable is to
force the conversation.

## Scalability

| Question | Common answers |
|---|---|
| Concurrent users (peak)? | 100 / 1K / 10K / 100K / 1M |
| Requests per second (peak)? | 10 / 100 / 1K / 10K |
| Data volume (year 1 / year 3)? | GB / TB / PB |
| Growth rate? | 10% / 50% / 100% / 10× per year |
| Peak-to-average ratio? | 2× / 5× / 10× / 100× |

## Performance

| Question | Common targets |
|---|---|
| API p50 / p95 / p99 response time | 50 / 100 / 200 ms |
| Page load time (interactive) | <2 s desktop, <3 s mobile |
| Database query p95 | <50 ms |
| Batch throughput | records/hour |

## Availability

| SLO | Downtime/year | Typical use case |
|---|---|---|
| 99% | 3.65 days | Internal/experimental |
| 99.9% | 8.76 hours | Standard business apps |
| 99.95% | 4.38 hours | E-commerce, SaaS |
| 99.99% | 52.6 minutes | Financial, critical B2B |
| 99.999% | 5.26 minutes | Life-critical, telecom |

Pick a target and design for it. "As high as possible" is not an SLO.

## Reliability

| Question | Targets |
|---|---|
| RPO (acceptable data loss window) | 0 / 5 min / 1 hour / 24 hours |
| RTO (recovery time) | 5 min / 1 hour / 4 hours / 24 hours |
| Backup frequency | continuous / hourly / daily |
| DR posture | single-region / active-passive / active-active multi-region |

## Security and compliance

- Authentication: password, SSO/SAML, OAuth, MFA, passkey?
- Authorization model: RBAC, ABAC, ACL?
- Data sensitivity: public, internal, confidential, PII, PCI, PHI?
- Compliance: GDPR, HIPAA, PCI DSS, SOC 2, ISO 27001, FedRAMP?
- Encryption: at rest (KMS), in transit (TLS 1.2+), end-to-end?
- Retention + right-to-be-forgotten obligations?

## Maintainability / operability

- Deployment frequency: multiple/day, daily, weekly, monthly?
- Deployment strategy: blue-green, canary, rolling, feature flags?
- On-call model: 24×7, business hours, best-effort?
- Observability: logs + metrics + traces, with clear ownership?
- Runbook expectation: every alert has one?

## Cost

- Budget: $/month total, or $/user, or $/transaction.
- Dev + ops headcount available to run this.
- Cost alert thresholds and ownership.
- Reserved / committed vs. on-demand strategy.

## Integration

- Upstream systems (what feeds us).
- Downstream systems (what we feed).
- Sync vs. async contracts per integration.
- SLAs we depend on, SLAs we owe.

## Template (paste into design doc)

```markdown
## Non-functional requirements

### Scale
- Concurrent users: <n>
- RPS peak: <n>
- Data volume year 1 / year 3: <x> / <y>

### Performance
- API p95: <n>ms
- Page interactive: <n>s

### Availability
- Target SLO: 99.<n>%
- RPO: <n>
- RTO: <n>

### Security
- Auth: <mechanism>
- Authz: <model>
- Data sensitivity: <level>
- Compliance: <frameworks>

### Operations
- Deploys/week: <n>
- On-call: <model>
- Observability: logs + metrics + traces via <stack>

### Cost
- Budget: $<n>/month
```

## Red flags

- Stakeholder says "we need to be as scalable as Netflix" but has 1K users.
  Design for 10× current, not 10,000×.
- No RPO/RTO stated for a system handling money. Ask before designing.
- "It should be secure" with no threat model. Make someone name the actors.
- Compliance requirements that weren't mentioned until month 6. Always ask
  about regulated data in the first conversation.
