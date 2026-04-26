---
name: cloud-architect
description: Design cloud architectures on AWS/Azure/GCP. Landing zones, Well-Architected reviews, cost optimization, migration (6Rs), disaster recovery, zero-trust security. Use when designing cloud topology, planning migrations, or optimizing spend/posture. Distinct from architecture-designer (generalist) and microservices-architect (distributed-systems patterns).
source: core
triggers: /cloud-architect, AWS architecture, Azure architecture, GCP architecture, landing zone, Well-Architected, cloud migration, cloud cost, disaster recovery, multi-cloud, cloud security review
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/cloud-architect
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# cloud-architect

Designs cloud architectures across AWS, Azure, and GCP. Focused on topology,
identity, networking, cost, and disaster recovery. Pairs naturally with the
`aws/`, `kubernetes/`, and `terraform/` stacks.

## When this skill is the right tool

- Designing a new workload on a specific cloud (or multi-cloud)
- Planning a migration (lift-and-shift, re-platform, re-architect)
- Running a Well-Architected / CAF-style review
- Designing a landing zone or multi-account/multi-subscription structure
- Cost optimization planning (reserved capacity, right-sizing, FinOps)
- Disaster recovery design with defined RTO/RPO

**Not for:**
- Generalist system design → `architect` system mode
- Distributed-systems resilience patterns → `architect` microservices mode
- Writing Terraform modules → `stacks/aws/` + hands-on coding
- Day-2 Kubernetes operations → `stacks/kubernetes/`

## Core workflow

1. **Discover** — current state, requirements, constraints, compliance needs, existing accounts/subs.
2. **Design** — pick services per capability; design topology, network, identity, data layer.
3. **Security** — zero-trust posture, identity federation, KMS, encryption everywhere, least privilege.
4. **Cost model** — right-size, use managed services deliberately, plan reserved/committed usage.
5. **Migration** — apply the 6Rs (rehost, replatform, refactor, repurchase, retire, retain); define waves; validate connectivity before cutover.
6. **Operate** — observability, automation, FinOps, continuous optimization.

### Validation checkpoints

**After design:** every component has a redundancy strategy; no single points of failure the NFRs forbid.

**Before migration cutover:** connectivity between source and target is validated:

```bash
aws ec2 describe-vpc-peering-connections \
  --filters "Name=status-code,Values=active"

az network vnet peering list \
  --resource-group rg --vnet-name my-vnet \
  --query "[].{Name:name,State:peeringState}"
```

**After migration:** application health confirmed at the load balancer / Traffic Manager, logs flowing, alarms wired.

**After DR test:** actual recovery matched the RTO/RPO. Document deltas.

## Quick chooser: service per capability

Use the appropriate `references/<cloud>.md` for details.

| Capability | AWS | Azure | GCP |
|---|---|---|---|
| Compute VM | EC2 | VM | Compute Engine |
| Managed container | ECS / EKS | ACI / AKS | Cloud Run / GKE |
| Serverless function | Lambda | Functions | Cloud Functions / Cloud Run |
| Object storage | S3 | Blob Storage | Cloud Storage |
| RDBMS managed | RDS / Aurora | Azure SQL / Postgres | Cloud SQL / AlloyDB |
| NoSQL managed | DynamoDB | Cosmos DB | Firestore / Bigtable |
| Queue / pub-sub | SQS + SNS | Service Bus / Event Grid | Pub/Sub |
| Secrets | Secrets Manager | Key Vault | Secret Manager |
| Identity | IAM + SSO | Entra ID + RBAC | IAM |
| Observability | CloudWatch + X-Ray | Monitor + App Insights | Cloud Monitoring + Trace |

## Must do

- Design for the stated availability SLO — not higher, not lower.
- Zero-trust identity by default: no long-lived keys, federated SSO, OIDC for CI.
- Everything in code (Terraform / Bicep / CloudFormation / Pulumi). No click-ops in prod.
- Cost allocation tags on every resource. Ownership is a blocking review item.
- Encrypt at rest (KMS-managed keys) and in transit (TLS 1.2+, no self-signed in prod).
- Multi-AZ by default; multi-region only when the NFRs justify it.
- Test DR runbooks. A plan that's never been executed is a wish list.
- Prefer managed services when the operational cost of self-hosting isn't earning its keep.

## Must not do

- Store secrets in code, env files committed to git, or resource tags.
- Skip encryption to save "a few milliseconds".
- Create vanity multi-region deployments for apps with no availability requirement.
- Over-architect — three accounts and a transit gateway for a 5-person startup is theater.
- Ignore cost reviews until the bill is a problem.
- Deploy without backup / restore tested.
- Run critical workloads on single-AZ managed services.

## IAM baseline (zero-trust)

```hcl
# Terraform — scoped role for an application
resource "aws_iam_role" "app" {
  name               = "app-${var.env}-order-service"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy" "app_s3" {
  role   = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject"]
      Resource = "${aws_s3_bucket.app.arn}/${var.env}/*"
      Condition = {
        StringEquals = {
          "aws:PrincipalTag/service" = "order-service"
        }
      }
    }]
  })
}
```

No wildcards in `Action`, no `"*"` in `Resource`, condition keys where they add value. See `stacks/aws/rules/iam-least-privilege.md` for deeper IAM discipline.

## Cost analysis starter

```bash
# AWS: top cost drivers in the last 30 days
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '30 days ago' +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --output table

# Azure: spend by resource group
az consumption usage list \
  --start-date $(date -d '30 days ago' +%Y-%m-%d) \
  --end-date   $(date +%Y-%m-%d) \
  --query "[].{RG:resourceGroup,Cost:pretaxCost,Cur:currency}" \
  --output table
```

Use these to seed a monthly FinOps review, not as the review itself.

## Output template

```markdown
# Cloud architecture: <workload>

## Context
<NFRs, compliance, budget, existing accounts>

## Topology
<Mermaid or cloud-canvas diagram>

## Identity & security
- SSO via <IdP>
- Per-account boundaries
- Encryption standards

## Network
- VPC/VNet layout
- Connectivity (peering, transit, VPN)
- Egress strategy

## Data layer
- Stores chosen per service with rationale
- Backup and DR posture

## Observability
- Logs / metrics / traces destination
- SLOs and their alerts

## Cost estimate
- Month 1 / steady state / peak scenarios
- Reserved vs. on-demand plan

## Rollout plan
- Phases, migration waves, rollback
```

## References

| Topic | File |
|---|---|
| AWS services, Well-Architected | `references/aws.md` |
| Azure services, Cloud Adoption Framework | `references/azure.md` |
| GCP services, reference architectures | `references/gcp.md` |
| Cost optimization + FinOps practices | `references/cost.md` |
