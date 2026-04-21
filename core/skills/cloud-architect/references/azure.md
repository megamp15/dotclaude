---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/cloud-architect/references/azure.md
ported-at: 2026-04-17
adapted: true
---

# Azure services (architect's cheat-sheet)

## Compute

| Service | Use when |
|---|---|
| Virtual Machines | Full OS control; lift-and-shift |
| VM Scale Sets | Autoscaled VM fleets |
| App Service | Managed PaaS for web apps; easy deployments |
| Azure Container Apps | Serverless containers with Dapr/KEDA-style scale |
| AKS | Managed Kubernetes |
| Functions | Event-driven serverless |
| Container Instances | Single-container tasks, short-lived |

Default to App Service for classic web apps, Container Apps for microservices without full k8s, AKS when k8s is the platform.

## Storage

| Service | Use when |
|---|---|
| Blob Storage (Hot/Cool/Archive) | Object storage with lifecycle tiers |
| Azure Files | SMB/NFS shared filesystem |
| Managed Disks | Block storage for VMs |
| Data Lake Storage Gen2 | Analytics lake on top of Blob |

Rules: storage accounts have `allowBlobPublicAccess = false`, TLS 1.2 enforced, shared keys disabled in favor of Entra ID, firewall scoped to needed networks.

## Database

| Service | Use when |
|---|---|
| Azure SQL Database | Managed SQL Server; elastic pools for many small DBs |
| Azure Database for PostgreSQL / MySQL | OSS RDBMS |
| Cosmos DB | Multi-model NoSQL; global distribution |
| Azure Cache for Redis | Managed Redis |
| Synapse Analytics | DWH |
| Azure Data Explorer | Time-series and log analytics |

Rules: prod databases in zone-redundant HA; geo-replicated read replicas where RTO/RPO demand it; Private Link endpoints, no public endpoints for prod.

## Networking

| Service | Use when |
|---|---|
| Virtual Network | Always |
| Application Gateway | L7 load balancing, WAF |
| Azure Front Door | Global L7, CDN, WAF |
| Load Balancer | L4 TCP/UDP |
| Traffic Manager | DNS-level traffic routing |
| API Management | Managed API gateway |
| Private Link | Private connections to PaaS services |
| ExpressRoute | Hybrid dedicated connectivity |
| VPN Gateway | Site-to-site VPN |
| Firewall | Stateful inspection, threat intel |

## Messaging / eventing

| Service | Use when |
|---|---|
| Service Bus | Enterprise queue + topic, FIFO, sessions, transactions |
| Event Grid | Pub/sub of discrete events across Azure services |
| Event Hubs | High-throughput ingestion; Kafka-compatible |
| Logic Apps | Orchestrated workflows with connectors |

Default: Service Bus for durable queues, Event Grid for system events, Event Hubs for streaming ingest.

## Security & identity

| Service | Use when |
|---|---|
| Entra ID (AAD) | Identity, SSO, MFA, Conditional Access |
| Key Vault | Keys, secrets, certs; managed identity access |
| Managed Identities | Workload identity — never use service-principal secrets |
| Defender for Cloud | Posture + workload protection |
| Sentinel | SIEM/SOAR |
| Policy + Blueprints | Governance at scale |

Rules: human access via Entra groups + Conditional Access; workload access via Managed Identities; no password-based service principals; Key Vault behind Private Link in prod.

## Observability

| Service | Use when |
|---|---|
| Azure Monitor (Logs/Metrics) | Default telemetry sink |
| Application Insights | APM for web apps and services |
| Log Analytics Workspace | Central query log store (KQL) |
| Managed Grafana / Prometheus | OSS-compatible dashboards |

## Subscription + management-group structure

```
Root Tenant
├── Management Group: platform
│   ├── Subscription: connectivity (hub VNet, Firewall, DNS)
│   ├── Subscription: identity
│   └── Subscription: management (Log Analytics, Sentinel)
├── Management Group: landing-zones
│   ├── Subscription: prod-<workload-1>
│   ├── Subscription: prod-<workload-2>
│   └── Subscription: nonprod-<workload-1>
└── Management Group: sandbox
    └── Subscription: sandbox-<team>
```

Policy scoped at management-group level: deny public IPs in prod, require tags, deny untrusted locations.

## Cloud Adoption Framework phases

| Phase | Focus |
|---|---|
| Strategy | Why are we moving? Business outcomes |
| Plan | Inventory, migration waves, skilling |
| Ready | Landing zone, identity, connectivity |
| Adopt | Migrate / innovate |
| Govern | Policy, cost management, compliance |
| Manage | Ops, monitoring, continuity |

Land the landing zone (Ready phase) before migrating workloads. Migrations into an un-governed account go sideways fast.
