---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/cloud-architect/references/cost.md
ported-at: 2026-04-17
adapted: true
---

# Cloud cost optimization (FinOps for architects)

The biggest cost wins come from architecture decisions, not from squeezing
10 % off instance sizes. Think in this order: *do we need this at all → is
this the right service → is it right-sized → is it purchased correctly.*

## Top-down checklist

1. **Do we need it?** Orphaned dev envs, forgotten prototypes, snapshots from
   2021 — find them first. Often 10–30 % of a bill.
2. **Right service?** Don't run a crontab on a 24×7 c5.large. Don't run a
   300 ms Lambda 24×7 either — at some duty cycle, Fargate/EC2 wins.
3. **Right size?** Match instance class to actual use. Burst instances for
   variable; ARM/Graviton for cost sensitivity; GPU tiers chosen per need.
4. **Right purchase model?** After right-sizing, move steady-state to
   reserved / committed / savings plans.

## Waste catalog (common, high-impact)

| Category | What to look for |
|---|---|
| Idle compute | VMs at <5 % CPU for days; Lambda with cold starts per request (cost floor) |
| Over-provisioned RDS / Cloud SQL | Instances sized for launch-day, never reviewed |
| Un-lifecycled storage | S3/Blob/GCS with no lifecycle; GB sitting in Standard tier |
| Orphaned resources | Detached volumes, unused elastic IPs, load balancers with no targets |
| NAT gateway egress | Surprisingly expensive; review traffic patterns, use VPC endpoints |
| CloudWatch Logs / Logging | Verbose logs with no retention; $$ per GB ingested |
| Inter-AZ traffic | Chatty services spread across AZs without need |
| Sandbox creep | Engineer sandbox accounts that were never cleaned up |

## Reserved / committed capacity

| Cloud | Mechanism | When to use |
|---|---|---|
| AWS | Savings Plans (Compute, EC2) / Reserved Instances | ≥70 % predictable usage over 1–3 years |
| Azure | Reservations, Savings Plans | Same |
| GCP | Committed Use Discounts (CUDs) + Sustained Use | Same; spend-based CUDs cover mixed workloads |

Rules of thumb:
- Start with Savings Plans / spend CUDs — flexible across instance families.
- 1-year terms unless the workload is obviously permanent.
- Cover ~70 % of steady-state demand, not 100 %. Leave headroom for change.

## Storage lifecycle

Every object store needs a lifecycle policy from day 1.

```yaml
# AWS S3 lifecycle example
Rules:
  - Id: move-logs-cold
    Status: Enabled
    Prefix: logs/
    Transitions:
      - Days: 30
        StorageClass: STANDARD_IA
      - Days: 90
        StorageClass: GLACIER
    Expiration:
      Days: 365
  - Id: delete-old-backups
    Status: Enabled
    Prefix: backups/
    Expiration:
      Days: 730
```

## Tagging (required for any cost review)

Mandatory tags on every resource:

| Tag | Example | Purpose |
|---|---|---|
| `Environment` | prod / staging / dev | Env filter |
| `Owner` | team-orders@corp | Accountability |
| `CostCenter` | cc-1234 | Chargeback |
| `Project` | checkout-v2 | Workload rollup |
| `ManagedBy` | terraform | Change path |

Enforce via SCPs / Azure Policy / GCP Org Policy. No tags → no deploy.

## Cost analysis starters

```bash
# AWS — top 10 services, last 30 days
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '30 days ago' +%F),End=$(date +%F) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE | \
  jq '.ResultsByTime[0].Groups | sort_by(.Metrics.UnblendedCost.Amount | tonumber) | reverse | .[0:10]'

# Azure — top resource groups
az consumption usage list \
  --start-date $(date -d '30 days ago' +%F) \
  --end-date   $(date +%F) \
  --query "[].{RG:resourceGroup,Cost:pretaxCost}" -o tsv | \
  awk '{a[$1]+=$2} END {for (r in a) printf "%-40s %.2f\n", r, a[r]}' | sort -k2 -n -r | head

# GCP — project costs
bq query --use_legacy_sql=false '
SELECT service.description, SUM(cost) AS cost
FROM `billing.export`
WHERE _PARTITIONTIME >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
GROUP BY 1 ORDER BY 2 DESC LIMIT 10'
```

## FinOps cadence

| Cadence | Ritual |
|---|---|
| Weekly | Anomaly review — did something double overnight? |
| Monthly | Service-by-service spend review with owners |
| Quarterly | Reserved / committed capacity plan |
| Annually | Architecture-level cost review — any service we should be off of? |

## Anti-patterns

- Asking "where can we cut 20 %?" without a tagged bill. You're flying blind.
- Right-sizing prod at the wrong time (right before a launch).
- Reserving 100 % of capacity. Demand shifts; keep flexibility.
- Optimizing pennies on compute while ignoring dollars on data transfer.
- Treating FinOps as a one-time project. It's continuous by design.
