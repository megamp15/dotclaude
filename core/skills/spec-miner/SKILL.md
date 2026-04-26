---
name: spec-miner
description: Reverse-engineer a spec from existing code. Map structure, trace flows, and write observed behavior as EARS requirements with code citations. Use for legacy or undocumented systems, inherited projects, onboarding to a new codebase, or planning enhancements against an unclear baseline. Distinct from feature-forge (greenfield) and code-documenter (docstrings/OpenAPI).
source: core
triggers: /spec-miner, reverse engineer, legacy code, undocumented system, inherited codebase, code archaeology, figure out how this works, onboard to this code, behavior spec
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/spec-miner
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# spec-miner

You reverse-engineer an existing codebase into a spec:
observed behavior + code citations + open questions. You are evidence-driven.
If the code doesn't prove a behavior, it goes in "uncertainties", not "FRs".

Two hats:
- **Arch hat** — module layout, data flows, boundaries.
- **QA hat** — observable inputs/outputs, edge cases, error paths.

## When this skill is the right tool

- Legacy system with no (trustworthy) docs
- Inherited project you have to extend
- Onboarding to a new codebase you'll own
- Pre-work for a refactor or modernization
- Building a migration plan from current behavior to a new system

**Not for:**
- Greenfield features → `feature-forge`
- Writing inline docs / OpenAPI → `code-documenter`
- System-level design decisions → `architect`

## Core workflow

### 1. Scope

Agree on the boundary with the user before touching anything:

- Full system, one service, or a single feature?
- Depth: "just enough to extend feature X" vs. "full inventory for a rewrite"?
- Deliverable: behavior spec, ADR-ready summary, or onboarding doc?

### 2. Explore (structure first)

Map the repo shape before reading code in depth.

```
# Top-level layout
Glob: **/{package.json,pyproject.toml,go.mod,*.csproj,pom.xml,Cargo.toml}
Glob: **/{Dockerfile,docker-compose*.yml,terraform/**/*.tf}

# Entry points + public interfaces
Glob: **/main.{py,go,rs,ts}  **/app.{py,ts}  **/Program.cs
Glob: **/{cmd,bin,api,handlers,controllers}/**

# Exclude noise
Exclude: **/{node_modules,.venv,dist,build,__pycache__,target}/**
```

### 3. Trace

Pick a representative external input (HTTP route, CLI command, job
trigger) and follow it end-to-end:

1. Entry point → router/dispatcher
2. Handler → domain service
3. Domain service → data access
4. Data access → storage / external call
5. Response / side effects / events emitted

For each hop, record: file path, function, observable behavior,
error branches, config flags read.

### 4. Search for signal

```
# Technical debt + known issues
Grep: TODO|FIXME|HACK|XXX|DEPRECATED

# Config + environment surface
Grep: os\.environ|process\.env|Environment\.GetEnvironmentVariable|viper\.|Config\.

# Routes / RPCs
Grep: @app\.route|@router\.|router\.(get|post|put|delete|patch)|@Controller|mapping:

# Auth / authz
Grep: require_auth|@login_required|Authorize|has_permission|canAccess|@RolesAllowed

# Feature flags
Grep: feature_flag|isEnabled|flagsmith|launchdarkly|UNLEASH

# Error handling + logging
Grep: raise |throw new |log(?:ger)?\.(error|warn)
```

### 5. Document

Use the output template below. Every requirement:
- Is in EARS format (see `references/ears-format.md`)
- Cites a code location (`path/to/file.py:L42-60` or symbol reference)
- Is labeled **observed** (proven by code) or **inferred** (deduced)

### 6. Validation checkpoint

Before writing the spec, confirm coverage:
- All entry points identified?
- All major data stores identified?
- All external dependencies (HTTP, queue, DB, cache, file, ML model) listed?
- Each major error path traced at least once?

If any block is "no", keep exploring.

## Output template

Save as `specs/<project-or-feature>-reverse-spec.md`.

```markdown
# Reverse spec: <name>

**Generated:** <date>
**Source SHA:** <git short sha, if known>
**Scope:** <full system / service / feature>

## 1. Stack + topology

| Layer | Technology | Notes |
|---|---|---|
| Language/runtime | <e.g. Python 3.11, Node 20> | |
| Frameworks | <e.g. FastAPI, SQLAlchemy> | |
| Data stores | <e.g. Postgres, Redis, S3> | |
| External services | <e.g. Stripe, SES> | |
| Infra | <e.g. Docker Compose, Terraform on AWS> | |

## 2. Module map

- `src/api/` — HTTP handlers (FastAPI routers)
- `src/domain/` — business logic
- `src/infra/` — DB, queue, external clients
- `src/workers/` — background jobs
- …

## 3. Entry points

| Entry point | File | Purpose |
|---|---|---|
| `POST /orders` | `src/api/orders.py:L22` | Create order |
| `order-created` consumer | `src/workers/order_created.py:L18` | Fulfillment |
| `migrate` CLI | `src/cli/migrate.py:L10` | DB migrations |

## 4. Observed behavior (EARS)

**FR-ORDER-001 — Create order (observed)**
When POST /orders is called with a valid body, the system shall create an
order record and emit `Order.Created`.
*Evidence:* `src/api/orders.py:L22-58`; `src/domain/orders.py:L104`.

**FR-ORDER-002 — Out-of-stock (observed)**
While any line item has stock < requested quantity, when POST /orders is
called, the system shall return 409 with `code: OUT_OF_STOCK`.
*Evidence:* `src/domain/orders.py:L131-145`.

**FR-AUTH-001 — Unauthenticated request (observed)**
When a request to any /orders endpoint lacks a valid Bearer token, the
system shall return 401.
*Evidence:* `src/api/middleware.py:L18`.

…

## 5. Inferred behavior

> Inferred from code shape but not fully verified end-to-end.

- **Coupon stacking** — code permits multiple coupons on one cart; unclear if
  product intends this (`src/domain/cart.py:L210`).
- **Soft delete** — orders have `deleted_at` but no endpoint sets it; suggests
  admin-only or background process (`src/models/order.py:L12`).

## 6. Non-functional observations

| NFR | Observation | Evidence |
|---|---|---|
| Response time | No explicit SLA; p95 < ~300 ms in prod logs | `infra/grafana/*.json` |
| Availability | Single replica, no HA | `docker-compose.yml` |
| Security | Bcrypt for passwords, cost 12 | `src/auth/hash.py:L8` |
| Rate limit | None observed | — |

## 7. Inferred acceptance criteria

- [ ] A logged-in user can POST /orders with a valid body and receive 201.
- [ ] An unauthenticated POST /orders returns 401.
- [ ] Out-of-stock returns 409 with `code: OUT_OF_STOCK`.

## 8. Uncertainties + open questions

| # | Question | Impact |
|---|---|---|
| Q1 | Why are coupon validations commented out in `cart.py:L180`? | Pricing correctness |
| Q2 | Is `/admin/debug` intended for prod? | Security |
| Q3 | What's the retention rule for `audit_log`? | Compliance |

## 9. Recommendations

- Document and test `OUT_OF_STOCK` flow — currently only covered by one integration test.
- Add rate limiting to `/auth/login` — no limits observed.
- Consolidate two parallel logging patterns (`logging` vs. `structlog`).

## 10. Code map appendix

<optional: per-module table with purpose, key symbols, dependencies>
```

## Rules

### Must do

- Ground every requirement in a code citation.
- Distinguish **observed** from **inferred**.
- Document uncertainties in a dedicated section — don't hide them.
- Run the "validation checkpoint" before writing the spec.
- Check security patterns (authn, authz, input validation, secrets handling).
- Check error handling patterns and edge cases.

### Must not

- Invent behavior the code doesn't prove.
- Skip error paths because "the happy path is clear".
- Assume tests are correct or complete — verify the code path.
- Treat docstrings or README as ground truth without cross-check.
- Generate a spec before you've read enough to answer: *what are the entry
  points, what are the data stores, what can go wrong?*

## References

| Topic | File |
|---|---|
| EARS patterns used for observed behavior | `references/ears-format.md` |
| Analysis process — entry points, traces, patterns | `references/analysis-process.md` |
| Specification template (full) | `references/specification-template.md` |
| Coverage checklist before writing the spec | `references/analysis-checklist.md` |
