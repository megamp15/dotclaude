---
name: architect
description: Architecture hub with five modes: system, rest-api, microservices, graphql, and cloud. Use for architecture decisions, API design, service boundaries, cloud platform tradeoffs, NFRs, ADRs, and design reviews. Loads mode-specific references on demand instead of exposing five separate top-level skills.
source: core
triggers: /architect, architecture, architecture design, system design, ADR, API design, REST API, OpenAPI, microservices, service boundaries, event-driven, GraphQL schema, GraphQL federation, cloud architecture, AWS architecture, Azure architecture, GCP architecture, non-functional requirements, NFR, scalability, reliability, latency, cost architecture
ported-from: https://github.com/Jeffallan/claude-skills (architecture-designer, api-designer, microservices-architect, graphql-architect, cloud-architect)
ported-at: 2026-04-17
adapted: true
---

# architect

One architecture skill, five modes. Pick the smallest mode that answers the
question and load only the references for that mode.

## Mode selection

| Signal | Mode |
|---|---|
| Whole-system shape, NFRs, ADRs, component boundaries | `system` |
| REST endpoints, resources, OpenAPI, errors, pagination, versioning | `rest-api` |
| Service decomposition, communication, data ownership, sagas/events | `microservices` |
| GraphQL schema, resolvers, federation, subscriptions, auth | `graphql` |
| AWS/Azure/GCP, network topology, cost, managed services | `cloud` |

If multiple modes apply, start with `system`, then load the narrow mode for
the area under debate. Do not produce a grand architecture when the user needs
an endpoint contract.

## Ground rules

- Start with constraints: users, traffic, data sensitivity, latency, budget,
  team size, compliance, deployment model, and migration limits.
- Make tradeoffs explicit. Architecture advice without "why this over the
  alternative" is decoration.
- Prefer reversible decisions where uncertainty is high. Mark irreversible or
  expensive-to-change choices clearly.
- Keep diagrams textual unless the user asks for a visual artifact.
- Finish with the next decision or experiment, not only a static design.

## References

Load these on demand:

- `system`: [`references/system.md`](references/system.md),
  [`references/system-patterns.md`](references/system-patterns.md),
  [`references/system-nfr-checklist.md`](references/system-nfr-checklist.md),
  [`references/system-adr-template.md`](references/system-adr-template.md)
- `rest-api`: [`references/rest.md`](references/rest.md),
  [`references/rest-patterns.md`](references/rest-patterns.md),
  [`references/rest-pagination.md`](references/rest-pagination.md),
  [`references/rest-versioning.md`](references/rest-versioning.md),
  [`references/rest-openapi-and-errors.md`](references/rest-openapi-and-errors.md)
- `microservices`: [`references/microservices.md`](references/microservices.md),
  [`references/microservices-decomposition.md`](references/microservices-decomposition.md),
  [`references/microservices-communication.md`](references/microservices-communication.md),
  [`references/microservices-data.md`](references/microservices-data.md),
  [`references/microservices-patterns.md`](references/microservices-patterns.md)
- `graphql`: [`references/graphql.md`](references/graphql.md),
  [`references/graphql-resolvers.md`](references/graphql-resolvers.md),
  [`references/graphql-federation.md`](references/graphql-federation.md),
  [`references/graphql-subscriptions-and-security.md`](references/graphql-subscriptions-and-security.md)
- `cloud`: [`references/cloud.md`](references/cloud.md),
  [`references/cloud-aws.md`](references/cloud-aws.md),
  [`references/cloud-azure.md`](references/cloud-azure.md),
  [`references/cloud-gcp.md`](references/cloud-gcp.md),
  [`references/cloud-cost.md`](references/cloud-cost.md)

## Output formats

For a design proposal:

```text
Context:
  <constraints and assumptions>

Recommendation:
  <one clear choice>

Why this:
  <tradeoffs and rejected alternatives>

Design:
  <components / API / data / deployment shape>

Risks:
  <top risks and mitigations>

Next step:
  <prototype, ADR, migration slice, or review gate>
```

For an architecture review:

```text
Findings:
1. <highest-risk issue with evidence>
2. ...

Tradeoffs:
  <what the current design optimizes for>

Recommendations:
  <ordered changes, with blast radius>
```

