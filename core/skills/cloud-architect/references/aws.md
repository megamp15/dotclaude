---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/cloud-architect/references/aws.md
ported-at: 2026-04-17
adapted: true
---

# AWS services (architect's cheat-sheet)

Focused on what matters when choosing services, not exhaustive docs.

## Compute

| Service | Use when |
|---|---|
| EC2 | Full OS control, long-running workloads, GPU/HPC, legacy VM migration |
| ECS (Fargate) | Containerized workloads without k8s operational cost |
| EKS | You already run (or must run) Kubernetes; multi-tenant platform |
| Lambda | Event-driven, spiky, <15 min, stateless |
| Batch | Large jobs with queue-based scheduling |
| Lightsail | Simple single-VM apps, low ops |

Prefer Fargate over EC2-backed ECS unless you need daemon-set / host-level access.
Prefer Lambda for glue code and event processing; avoid for sustained high-throughput APIs (cost + cold-start).

## Storage

| Service | Use when |
|---|---|
| S3 Standard | Default object storage |
| S3 IA / Glacier IR / Deep Archive | Cold tiers — use lifecycle policies |
| EBS gp3 | Default block storage; prefer gp3 over gp2 (cheaper, faster defaults) |
| EFS | Shared POSIX filesystem across many EC2/ECS tasks |
| FSx (Lustre/Windows) | Specialized HPC or Windows shares |

S3 rules: versioning on for anything important; server-side encryption default; block public access at account level; object ownership → bucket owner enforced.

## Database

| Service | Use when |
|---|---|
| RDS (Postgres/MySQL) | Standard relational needs, managed backups, Multi-AZ |
| Aurora | Higher scale than RDS, read replicas, serverless v2 for spiky load |
| DynamoDB | Key-value / document; single-digit-ms access at any scale; careful data modeling required |
| ElastiCache (Redis/Memcached) | In-memory cache; sessions; real-time leaderboards |
| Redshift / Athena | Analytics (warehouse vs serverless SQL on S3) |
| Neptune | Graph |
| OpenSearch | Search and log analytics |

Rules: always Multi-AZ for prod RDS; automated backups + PITR enabled; use IAM DB auth or Secrets Manager rotation, not static passwords; enable Performance Insights.

## Networking

| Service | Use when |
|---|---|
| VPC | Always — this is the perimeter |
| ALB | HTTP/HTTPS with path/host routing, WebSockets |
| NLB | TCP/UDP, extreme performance, static IPs |
| API Gateway | Public REST/HTTP APIs with throttling, auth, WAF integration |
| Route 53 | Managed DNS, health-checked failover, geolocation routing |
| CloudFront | CDN, TLS termination at edge, WAF |
| PrivateLink | Expose services privately across VPCs/accounts |
| Transit Gateway | Hub-and-spoke for many VPCs and on-prem |
| VPN / Direct Connect | Hybrid connectivity |

Baseline VPC: 2–3 AZs, public subnets for load balancers only, private subnets for workloads, isolated subnets for data; NAT Gateway per AZ for resilience (or VPC endpoints to avoid NAT costs).

## Messaging / eventing

| Service | Use when |
|---|---|
| SQS | Point-to-point queues, decoupling, retry |
| SNS | Pub/sub fan-out; trigger Lambda/SQS/HTTP |
| EventBridge | Event bus with schema registry; cross-account, cross-service events |
| Kinesis Data Streams | Ordered streaming, replay, multiple consumers |
| MSK | Managed Kafka for teams already invested in Kafka |
| Step Functions | Orchestration with visual state machines, long-running workflows |

Default: start with SQS + SNS, graduate to EventBridge when you need rules and cross-account.

## Security & identity

| Service | Use when |
|---|---|
| IAM | Identity, roles, policies — always |
| IAM Identity Center (SSO) | Human access across accounts |
| KMS | Encryption key management; CMKs for compliance |
| Secrets Manager | Rotated secrets, DB credentials |
| Parameter Store | Config + non-rotated secrets (cheaper) |
| WAF | HTTP-layer filtering; use for public APIs |
| Shield Advanced | DDoS protection for regulated workloads |
| GuardDuty | Threat detection; enable in every account |
| Security Hub | Aggregated posture view |
| Macie | PII discovery in S3 |

Rules: no long-lived IAM user keys — use SSO for humans, OIDC for CI, roles for compute. Every account has GuardDuty, CloudTrail (org-level), Config. KMS keys scoped by purpose, not one master key.

## Observability

| Service | Use when |
|---|---|
| CloudWatch Logs | Default log sink; set retention per log group |
| CloudWatch Metrics | Default metrics; publish custom with EMF |
| X-Ray | Distributed tracing (or use OpenTelemetry → CloudWatch) |
| CloudWatch Alarms | Alerting + auto-scaling triggers |
| Managed Grafana / Prometheus | When CloudWatch isn't enough |

Rule of thumb: every service publishes structured JSON logs, named metrics, and traces with correlation IDs. Alerts wired to the on-call channel, each with a runbook.

## Well-Architected pillars (condensed)

| Pillar | Litmus test |
|---|---|
| Operational excellence | Deploys, alarms, and runbooks exist and are rehearsed |
| Security | Least privilege, encryption everywhere, auditable |
| Reliability | Multi-AZ by default; DR tested; graceful degradation |
| Performance efficiency | Right-sized; using managed services deliberately |
| Cost optimization | Tagged; reviewed monthly; reserved where steady-state |
| Sustainability | Graviton/ARM where possible; auto-scale down; lifecycle policies on data |

## Account structure (landing zone)

For any non-trivial org, use Organizations with separate accounts:

```
management (root) — SSO, billing, SCPs
├── log-archive           (immutable logs)
├── audit                 (Security Hub, GuardDuty aggregator)
├── shared-services       (Transit Gateway, central DNS)
├── prod-<workload-1>
├── prod-<workload-2>
├── staging-<workload-1>
└── sandbox-<developer>
```

Enforce: SCPs deny root user actions, require MFA, deny creating long-lived keys in prod.

## Migration: 6Rs

| R | Meaning | When |
|---|---|---|
| Rehost | Lift and shift, VM → EC2 | Time-critical, low-change |
| Replatform | Small changes, e.g. SQL Server → RDS | Modernize lightly |
| Repurchase | Replace with SaaS | License ends, commodity capability |
| Refactor | Rewrite for cloud-native | Long-term, high-value workload |
| Retire | Turn off | Unused or duplicate |
| Retain | Keep on-prem | Compliance, latency, complexity |

Plan in waves: low-risk workloads first, stateful last. Never do all your databases in one wave.
