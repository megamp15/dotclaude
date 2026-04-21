---
source: stacks/aws
---

# Stack: AWS

Conventions for projects that target AWS. Layers on `core/`. Usually
stacks alongside `terraform` (for infra), `docker`, `github-actions`.

## The premise

AWS is three things at once:

1. A giant set of primitives (EC2, S3, IAM, etc.) — useful but sharp.
2. A cost surface — every resource is a running meter.
3. A security surface — one misconfigured IAM role, one open bucket, one leaked access key can go badly.

Every piece of AWS work should answer: **what does this cost, who can
access it, and how is it deployed reproducibly?**

## Default discipline

- **Infrastructure as Code.** Terraform (preferred for multi-cloud, mature, widespread), AWS CDK (TypeScript/Python — good if you want code not config), or CloudFormation. Console clicks for exploration only; production state in IaC.
- **Per-account environment separation.** Separate AWS accounts for dev / staging / prod. Not separate VPCs in one account. AWS Organizations + Control Tower for the setup.
- **Everything tagged.** Cost allocation depends on tags: `Environment`, `Project`, `Owner`, `CostCenter`, `ManagedBy=terraform`. A tagging standard enforced at apply time (tag policies or Terraform validation).
- **Region-pinned.** Don't let resources wander into `us-east-1` by default. Pick a region deliberately; set `AWS_REGION` or provider-level region explicitly.
- **Stateless compute over stateful when possible.** Stateful = harder to scale, harder to upgrade, harder to replace.

## IAM — do this right, fewer incidents

### Root account
- MFA on the root user.
- Root access keys: deleted.
- Billing alerts configured.
- Never use root for day-to-day work. Create IAM users/SSO immediately.

### IAM users vs SSO

- **SSO (AWS IAM Identity Center)** for humans whenever possible. Shorter-lived creds, central management, MFA enforceable, federated to your IdP.
- **IAM users** only for programmatic service accounts that can't use roles/SSO (rare these days). Prefer roles+STS.

### Roles + STS

- Compute (EC2, Lambda, ECS, EKS) gets an **IAM role**, not a baked-in key.
- Cross-account access: **role assumption** with external-id where appropriate.
- CI/CD: **OIDC federation** from GitHub Actions / GitLab / etc. — no long-lived keys in secret stores.

### Policy discipline

- **Least privilege.** Start with deny-all, add specific permissions. Avoid `*:*` or `AdministratorAccess` for anything but the admin role.
- **Avoid managed policies** where feasible for production workloads — AWS-managed ones are broader than your app needs. Write specific policies.
- **Resource ARNs scoped** — `arn:aws:s3:::my-bucket/*` not `arn:aws:s3:::*`.
- **Condition keys** for extra controls: `aws:SourceVpce`, `aws:SourceIp`, `aws:PrincipalTag`, MFA required.
- **Access Analyzer** turned on — catches wildcards and unintended public exposure.

## Networking baseline

- **VPC per environment.** Don't share a prod VPC with dev.
- **Subnets**: private for compute, public only for ALBs / NAT gateways / bastion (if you need one). Production compute doesn't sit in public subnets.
- **NAT Gateway** for egress from private subnets — pricey, but required. Consider VPC Interface Endpoints (PrivateLink) for AWS service traffic to avoid NAT costs for S3, DynamoDB, etc.
- **Security Groups** as stateful allow-lists. **NACLs** are stateless — avoid as primary control; use for extra defense-in-depth only when needed.
- **Route53** for DNS. Private hosted zones for internal names.
- **VPC Flow Logs** enabled, shipped to S3 or CloudWatch, for forensic/debugging needs.

## Common services — conventions

### S3

- **Block Public Access at account level.** On. Always. Every account. Override only for explicit use cases (static websites, public distribution).
- **Bucket names**: globally unique; project-prefixed for findability (`acme-billing-prod-logs`).
- **Versioning** on for anything important; **MFA Delete** for irreplaceable.
- **Server-side encryption** default (SSE-S3 or SSE-KMS). SSE-KMS with a customer-managed key for sensitive data.
- **Lifecycle policies** to transition to IA / Glacier / Deep Archive and expire old data.
- **Bucket policy** scoped to your accounts/roles; no `"Principal": "*"` unless a public bucket (and then really make sure).

### IAM roles + EC2

- EC2 gets an **instance profile** (role attached to the EC2). Apps inside get creds via IMDSv2 (force IMDSv2 to avoid SSRF exploits).
- **User data** for bootstrapping; prefer AMIs baked with Packer for reproducibility.

### Lambda

- **Memory size drives CPU share** — don't under-size; often cheaper to raise memory because CPU scales with it.
- **Timeout** set realistically; default 3s is often wrong. For long tasks: Step Functions, not a 15-minute Lambda.
- **VPC Lambdas cost startup time** (ENI attach). Avoid unless you need to reach private resources.
- **Reserved concurrency** to cap blast radius; otherwise a runaway Lambda can hit account-wide limits.
- **Log retention** on the CloudWatch Log Group — default is never-expire → unbounded cost.

### RDS / Aurora

- **Multi-AZ** for production; it's cheap insurance.
- **Encryption at rest** on; enabled at creation (can't toggle on an existing instance easily).
- **Automated backups** with reasonable retention (7-35 days).
- **Read replicas** for read scaling, not availability — failover to a replica isn't automatic.
- **Parameter groups** per environment; don't use `default.*`.
- **Performance Insights** on; cheap observability.
- **IAM auth** where possible over password auth.
- **Secrets Manager** for passwords with rotation.

### EKS

- See `stacks/kubernetes` for workload patterns. AWS-specific:
  - **IRSA** (IAM Roles for Service Accounts) — every workload needing AWS access gets its own IAM role via OIDC. Not node-level roles shared with all workloads.
  - **Managed Node Groups** or **Karpenter**. Karpenter is the modern default — faster, more efficient.
  - **AWS Load Balancer Controller** for real ALBs/NLBs from K8s Services.
  - **VPC CNI** default; watch pod density per node (IP limits).

### ECS + Fargate

- Fargate = no servers to patch; modest premium. Default choice if you don't need custom EC2-level tuning.
- **Service discovery** via ECS Service Connect or AWS Cloud Map.
- **Task role** + **execution role** are different things; task role for app perms, execution role for ECS to pull images and ship logs.

### SQS / SNS / EventBridge

- **SQS** for point-to-point queues.
- **SNS** for fanout pub/sub.
- **EventBridge** for rich rule-based routing (schema registry, third-party sources). Increasingly the right choice for new designs.
- **Dead Letter Queues** on every SQS main queue. Without a DLQ, poison messages loop forever and rack up charges.
- **Visibility timeout** sized to ≥ max processing time (otherwise duplicate processing).

### KMS

- **Customer-managed keys** (CMKs) for sensitive data; AWS-managed keys are fine for most things.
- **Alias** (`alias/app-prod`) used everywhere — makes key rotation painless.
- **Key policies** scoped tightly; IAM alone doesn't gate KMS.

### CloudWatch Logs

- **Log groups** per app per environment; retention set explicitly.
- **Metric filters** for key log events (errors, specific HTTP statuses).
- **Alarms** on metric filters for paging events.

## Cost discipline

- **AWS Budgets** with alerts per account. First alert at 50%, second at 80%, third at 100%.
- **Cost Explorer** reviewed weekly while cost patterns stabilize; monthly afterward.
- **Tags** enforced in CI (Terraform plan step can check) so Cost Explorer can slice by project/owner.
- **Stopped != free.** EBS volumes, Elastic IPs, NAT Gateways, snapshots all cost money when "nothing is running."
- **Savings Plans / Reserved Instances** only once usage is stable; don't lock in dev/experimental workloads.
- **Free tier** is helpful for learning; expires; set an alarm for when you drop off it.

## Secrets

- **Secrets Manager** for application secrets (passwords, API keys). Rotation enabled where supported.
- **SSM Parameter Store** for configuration (including `SecureString` for low-value secrets). Cheaper than Secrets Manager.
- **Never** put secrets in Lambda env vars, user-data, task definitions, or anywhere IaC state stores in plaintext.

## Monitoring + alerting

- **CloudWatch** as the AWS-native default; **Prometheus/Grafana/Datadog/etc.** if you're already using them.
- **AWS Config** for compliance tracking (what resources exist, what their config is). Turn on recording.
- **CloudTrail** in every account, logs to a central S3 bucket in a separate account. Enables audit/forensics.
- **GuardDuty** on — cheap; catches real threats.
- **Security Hub** + **Inspector** for vulnerability posture.

## Do not

- Do not use root user for anything except initial setup.
- Do not create long-lived access keys if you can avoid it. Prefer roles + STS.
- Do not use `*` in IAM policies without a very good reason and a comment.
- Do not disable Block Public Access at the account level.
- Do not run production in a single AZ.
- Do not skip tagging — cost attribution breaks downstream.
- Do not commit `.aws/credentials` or access keys to git. Rotate immediately if accidentally exposed.
- Do not ignore GuardDuty findings.
- Do not deploy to production from a developer laptop — CI/CD with audit trail.
