---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/cloud-architect/references/gcp.md
ported-at: 2026-04-17
adapted: true
---

# GCP services (architect's cheat-sheet)

## Compute

| Service | Use when |
|---|---|
| Compute Engine | VM; sustained-use discounts automatic |
| GKE (Autopilot) | Managed Kubernetes without node ops |
| GKE Standard | K8s with node control |
| Cloud Run | Serverless containers, request-driven autoscale |
| Cloud Functions (2nd gen) | Event-driven, small units |
| App Engine Standard/Flex | Legacy PaaS; default to Cloud Run for new work |

Default: Cloud Run for services, GKE Autopilot for k8s-native workloads.

## Storage

| Service | Use when |
|---|---|
| Cloud Storage | Object storage; multi-region / dual-region / regional |
| Persistent Disk | Block storage |
| Filestore | NFS shared filesystem |

Rules: uniform bucket-level access on, no public access unless explicitly needed, object versioning + lifecycle rules.

## Database

| Service | Use when |
|---|---|
| Cloud SQL | Managed MySQL/Postgres/SQL Server |
| AlloyDB | High-performance Postgres-compatible; analytics-friendly |
| Spanner | Global, strong-consistency RDBMS; high-scale |
| Firestore | Document DB with real-time sync |
| Bigtable | Wide-column, high-throughput |
| BigQuery | Serverless DWH |
| Memorystore | Managed Redis/Memcached |

## Networking

| Service | Use when |
|---|---|
| VPC | Always; VPCs are global in GCP |
| Cloud Load Balancing | Global anycast L7 (HTTPS) or L4 |
| Cloud CDN | Edge caching |
| Cloud Armor | WAF, DDoS protection |
| Cloud NAT | Outbound from private subnets |
| Cloud Interconnect / VPN | Hybrid |
| Private Service Connect | Private endpoints to Google + third-party services |
| Shared VPC | Central network team owns, service projects consume |

GCP VPCs are global — a single VPC spans all regions. Plan subnets per region.

## Messaging / eventing

| Service | Use when |
|---|---|
| Pub/Sub | Default pub/sub and queue (supports pull + push) |
| Eventarc | Event routing from Google services |
| Cloud Tasks | Scheduled / delayed task execution |
| Workflows | Serverless orchestration |
| Dataflow | Streaming + batch processing (Apache Beam) |

Pub/Sub is the default — it covers most queue and pub/sub needs.

## Security & identity

| Service | Use when |
|---|---|
| IAM | Roles, conditions, resource-level bindings |
| Workload Identity Federation | Federate OIDC (GitHub, CircleCI) into IAM — no long-lived keys |
| Workload Identity (GKE) | K8s service accounts → GCP service accounts |
| Secret Manager | Secrets |
| Cloud KMS | Keys; CMEK support across services |
| Binary Authorization | Container image provenance enforcement |
| Security Command Center | Posture + threat detection |

Rules: no service-account JSON keys — use Workload Identity Federation or short-lived impersonation. Organization policies enforce location, deny public IPs, require CMEK where compliance demands.

## Observability

| Service | Use when |
|---|---|
| Cloud Logging | Centralized logs, with log buckets and sinks |
| Cloud Monitoring | Metrics + alerting |
| Cloud Trace | Distributed tracing |
| Cloud Profiler | Production profiling |
| Managed Service for Prometheus | OSS Prometheus at scale |

## Organization structure

```
Organization
├── Folder: platform
│   ├── Project: networking-hub
│   ├── Project: logging-monitoring
│   └── Project: security
├── Folder: prod
│   ├── Project: workload-a-prod
│   └── Project: workload-b-prod
├── Folder: nonprod
└── Folder: sandbox
```

Organization policies set at the org/folder level; projects inherit. Shared VPC for centrally managed networks; one host project, many service projects.

## Cloud Architecture Framework pillars

| Pillar | Check |
|---|---|
| Operational excellence | Deploys automated; SRE golden signals monitored |
| Security | IAM scoped, CMEK where regulated, VPC-SC for data perimeters |
| Reliability | Regional with failover; SLOs and error budgets defined |
| Performance | Services right-sized; autoscaling configured |
| Cost optimization | CUDs/SUDs applied; lifecycle on storage; BigQuery slot allocation |

## Gotchas

- VPCs are global but resources are regional/zonal — deliberate about placement.
- Service accounts can impersonate each other if granted — audit these grants.
- `roles/owner` is effectively superuser — almost never the right binding.
- Cloud Run has per-request billing; long-running cron should go to GKE/Compute Engine.
