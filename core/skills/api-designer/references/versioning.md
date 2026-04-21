---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/api-designer/references/versioning.md
ported-at: 2026-04-17
adapted: true
---

# API versioning

Choose a strategy before you ship. Changing the versioning approach later is
more painful than the original decision.

## What counts as a breaking change

**Breaking (requires a new version):**
- Removing or renaming a field
- Changing a field's type or semantics
- Adding a required request field
- Changing response structure
- Removing an endpoint
- Changing status codes for the same scenario
- Changing auth mechanism

**Non-breaking (can ship in the current version):**
- Adding new endpoints
- Adding optional request fields (with defaults that match prior semantics)
- Adding new optional response fields (clients must ignore unknowns)
- Bug fixes that match documented behavior
- Performance improvements
- Adding new acceptable enum values *if clients expect unknown values*

## Strategies compared

| Strategy | Example | Pros | Cons |
|---|---|---|---|
| **URI** | `/v1/orders` | Visible, cacheable, simple | URI proliferation, less REST-y |
| **Header** | `Accept: application/vnd.api.v1+json` | Stable URIs | Invisible, harder to debug |
| **Query param** | `/orders?version=1` | Simple, visible | Pollutes query space |
| **Date-based** | `/2026-04-17/orders` | Granular, no confusion | Harder to communicate |

### Recommendation

**Default to URI versioning with major versions only (`v1`, `v2`, `v3`).**
It's the most discoverable, easiest to cache, easiest to route, easiest to
debug. Major versions only — no `v1.2.3`.

Stripe's date-based scheme works at their scale but is overkill for most teams.

## Version lifecycle

```
  Introduction        Deprecation        Sunset
       │                   │                │
       ▼                   ▼                ▼
   ┌──────┐ ───────── ┌────────┐ ────── ┌───────┐
   │ v1   │           │v1 deprec│        │v1 gone│
   │  v2  │ ───────── │   v2   │ ─────▶ │  v2   │
   └──────┘           └────────┘        └───────┘
        6–12 months supporting both     410 Gone
```

### Phase 1: Introduction

Ship `v2` alongside `v1`. Announce via:
- Changelog and migration guide.
- Dashboard notification for registered devs.
- Email to key integrators.

### Phase 2: Deprecation

```http
HTTP/1.1 200 OK
Deprecation: true
Sunset: Sun, 17 Oct 2026 00:00:00 GMT
Link: <https://api.example.com/v2/orders/123>; rel="successor-version"
Link: <https://api.example.com/docs/migration-v1-to-v2>; rel="deprecation"
```

Headers use RFC 8594. Deprecation period should be at least 6 months,
preferably 12 for paid APIs.

### Phase 3: Sunset

```http
HTTP/1.1 410 Gone
Content-Type: application/problem+json

{
  "type": "https://api.example.com/errors/version-sunset",
  "title": "API version sunset",
  "status": 410,
  "detail": "v1 was sunset on 2026-10-17. Use v2.",
  "code": "VERSION_SUNSET",
  "migration_url": "https://api.example.com/docs/migration-v1-to-v2"
}
```

Keep the 410 response for 30+ days; some clients won't have rotated off yet.

## Communicate early, communicate often

- API response headers (primary signal for machines)
- Changelog / release notes
- Emails to registered integrators
- Status-page announcements
- Documentation banner during deprecation window
- Developer-dashboard notifications

Silence is the root cause of most "they sunset us without warning" complaints.

## Migration guides

Every breaking change needs a migration guide. Minimum structure:

```markdown
# Migrating from v1 to v2

## Summary
- [Headline changes, 2–5 bullets]

## Breaking changes

### User — name split into first_name + last_name
**v1:**
```json
{ "name": "John Doe" }
```
**v2:**
```json
{ "first_name": "John", "last_name": "Doe" }
```
**Migration:** split existing `name` by first whitespace for backfill.

## Non-breaking additions
- [New optional fields]
- [New endpoints]

## Timeline
- Announced: 2026-04-17
- Deprecated: 2026-04-17
- Sunset: 2026-10-17
```

## Version discovery

```http
GET /
→ 200
{
  "versions": {
    "v1": {
      "status": "deprecated",
      "sunset": "2026-10-17",
      "docs": "https://api.example.com/docs/v1"
    },
    "v2": {
      "status": "current",
      "docs": "https://api.example.com/docs/v2"
    },
    "v3": {
      "status": "beta",
      "docs": "https://api.example.com/docs/v3"
    }
  }
}
```

## OpenAPI per version

Keep one OpenAPI spec per major version under `docs/api/v{N}.yaml`. Don't
try to cram multiple versions into a single spec — the `servers` trick is
cute but obscures reality.

## Rules

- Start at `v1`, not `/api/`. Version from day one.
- Major versions only.
- Support at least N and N-1 concurrently.
- Deprecation period ≥ 6 months.
- Announce before shipping deprecation.
- `Deprecation` and `Sunset` headers on every response from a deprecated version.
- After sunset, return 410 with a migration link.

## Anti-patterns

- **Breaking changes without a version bump.** Explain this to your customers' incident commanders.
- **Too many versions in flight.** v5 while still supporting v1? No.
- **Short deprecation windows (days/weeks).** Unless it's a security bug, give at least 6 months.
- **Surprise sunsets.** Silence → shipped breakage.
- **Inconsistent versioning across endpoints.** One API, one version strategy.
- **Per-endpoint versions.** `POST /v1/orders` + `GET /v2/orders`? Madness.
