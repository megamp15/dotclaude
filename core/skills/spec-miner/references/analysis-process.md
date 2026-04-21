---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/spec-miner/references/analysis-process.md
ported-at: 2026-04-17
adapted: true
---

# Analysis process

Order: **shape → entry points → trace one path → widen → patterns → write**.

## 1. Shape

Figure out what kind of project this is before reading code in depth.

```
# Manifests
Glob: **/{package.json,pyproject.toml,requirements.txt,go.mod,Cargo.toml,pom.xml,*.csproj}

# Config
Glob: **/{.env.example,config/**,settings/**,*.yaml,*.yml,*.toml}

# Infra
Glob: **/{Dockerfile,docker-compose*.yml,terraform/**,helm/**,k8s/**}
```

Read one manifest per language to pin runtime, framework, test runner, and
key dependencies.

## 2. Entry points

Classify every way the outside world gets in:

| Class | Patterns |
|---|---|
| HTTP | `@app.route`, `@router.get|post`, `app.get`, `@Controller`, `mapping:` |
| CLI | `argparse`, `click`, `typer`, `cobra`, `yargs`, `commander` |
| Queue consumer | `@consume`, `kafka.*Consumer`, `sqs.receive`, `@RabbitListener` |
| Cron / scheduler | `cron`, `schedule`, `apscheduler`, `celery beat` |
| gRPC | `.proto`, `implements *Server`, `*ServiceBase` |
| Event / webhook | `webhook`, `/hooks/`, `stripe_webhook`, `github_webhook` |
| Static assets | `templates/`, `public/`, `routes/` in SSR |

Record each with file + line + purpose.

## 3. Trace one path

Pick the most business-critical entry point and follow it to completion:

1. Route → handler
2. Handler → request validation
3. Handler → domain service
4. Domain service → data access + external calls
5. Response assembly → response
6. Side effects: events emitted, cache writes, audit logs, notifications

At each hop record:
- file + line
- what it reads (headers, body, env, config, flags)
- what it writes (DB, cache, queue, log)
- what it throws / returns

## 4. Widen

Once one path is fully traced, widen to adjacent paths:

- Other methods on the same resource (GET, PUT, DELETE siblings of your traced POST)
- Sibling resources in the same domain
- Error paths off the critical flow

## 5. Patterns to find

Routinely sweep for cross-cutting concerns. Each one becomes a section or
NFR in the final spec.

### Authentication + authorization

```
Grep: (Bearer|JWT|OAuth|session_id|auth_token)
Grep: (@login_required|@require_auth|@Authorize|has_permission|canAccess|@RolesAllowed)
Grep: (middleware|filter|interceptor).*auth
```

### Validation

```
Grep: (pydantic|zod|joi|yup|class-validator|@Valid|ModelState)
Grep: (schema|validate|validator)
```

### Data access

```
Grep: (sqlalchemy|prisma|sequelize|typeorm|gorm|ef\.|DbContext)
Grep: (SELECT|INSERT|UPDATE|DELETE).*FROM
Grep: (execute|query|raw)\(
```

### External calls

```
Grep: (httpx|requests|axios|fetch|http\.Get|HttpClient)
Grep: (boto3|azure|google\.cloud|@azure|@aws-sdk)
Grep: (redis|kafka|rabbitmq|nats)
```

### Error handling

```
Grep: (raise |throw new |except |catch \()
Grep: (logger\.error|log\.Error|console\.error)
Grep: (HTTPException|ApiError|custom error classes)
```

### Feature flags + config

```
Grep: (os\.environ|process\.env|Environment\.)
Grep: (feature_flag|isEnabled|launchdarkly|unleash|flagsmith)
```

### Secrets + security posture

```
Grep: (SECRET|TOKEN|PASSWORD|API_KEY|PRIVATE_KEY)
Grep: (bcrypt|argon2|scrypt|pbkdf2)
Grep: (crypto|encrypt|decrypt|AES|RSA)
```

### Tech debt signals

```
Grep: (TODO|FIXME|HACK|XXX|DEPRECATED|WIP|REVIEW)
```

## 6. Data model

- Find migrations or ORM model definitions.
- Build an entity list with: fields, types, nullability, indexes, relationships.
- Note soft-delete columns (`deleted_at`, `is_active`) and audit columns
  (`created_by`, `updated_at`).
- Note audit/event tables (often a clue to business-critical operations).

## 7. External integrations

For every outbound call, record:
- Service name
- Auth mechanism (token source, rotation)
- Failure mode observed (retry? circuit breaker? fall-through?)
- Timeout + retry policy (if any)
- Rate limit awareness (if any)

## 8. Logs + metrics + observability

- Logging library and format (JSON? plaintext? correlation IDs?)
- Metrics emitted (Prometheus? StatsD? OpenTelemetry?)
- Tracing (OTel, Datadog, New Relic)
- Health / readiness endpoints

## 9. Tests

Treat tests as documentation with opinions:

- Which behaviors have tests and which don't.
- Integration vs. unit balance.
- Gaps where critical paths lack coverage (flag these as recommendations).

## 10. Writing the spec

You are done exploring when you can answer, from the code:

- What are the entry points?
- What can you do with them?
- What can go wrong at each one?
- Where does data live?
- What external systems are touched?
- What's the authentication + authorization model?

Only then write the spec. See `specification-template.md`.

## Budgeting

| Scope | Rough time |
|---|---|
| Single feature, small service | 1–2 h exploration → 1 h writeup |
| Full service | 4–8 h exploration → 2–3 h writeup |
| Multi-service platform | split into per-service reverse specs; aggregate |
