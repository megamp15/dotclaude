---
source: stacks/aws
name: iam-least-privilege
description: IAM policy authoring — scope actions + resources tightly, prefer roles to keys, use condition keys, avoid wildcards. Load when writing or reviewing IAM policies, trust policies, or resource policies.
triggers: iam, iam policy, trust policy, resource policy, assume role, sts, aws:PrincipalTag, aws:SourceVpce, kms policy, s3 bucket policy, least privilege
globs: ["**/*.tf", "**/*.tfvars", "**/policies/**/*.json", "**/*-policy.json", "**/*-trust.json"]
---

# IAM least privilege

The single largest source of AWS incidents. Get this right and most
other problems are survivable; get it wrong and one leaked credential
is a company-defining event.

## The four questions for every policy

1. **Who?** (Principal / trust policy.) Which entity is this policy for?
2. **Can do what?** (Action list.) The minimum actions required — no `service:*` unless justified.
3. **To which resources?** (Resource ARN list.) Scoped ARNs, not `*`.
4. **Under what conditions?** (Condition block.) IP, VPC endpoint, MFA, source account, tags.

If any answer is "everything" or "anything", go back and narrow.

## Action discipline

### Start narrow, grow from evidence

- Start with deny-all, add actions as workloads fail with permission errors.
- Use **CloudTrail + Access Analyzer** to see what the principal actually calls; build policy from that.
- AWS **IAM Access Analyzer → Policy Generation** can generate policies from CloudTrail history.

### Avoid patterns

- `*:*` — administrator. Limit to genuine admins. Break-glass only with MFA + alerting.
- `service:*` — whole-service access. Prefer explicit action list.
- `service:List*` + `service:Get*` + `service:Describe*` — "read" is a useful convention but verify the list covers only read.
- `iam:PassRole` with `Resource: "*"` — lets the principal assign any role to any service. Scope to specific role ARNs:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::123:role/MyAppRole",
    "Condition": { "StringEquals": { "iam:PassedToService": "lambda.amazonaws.com" } }
  }
  ```

### Useful action patterns

- `s3:GetObject` + `s3:PutObject` on a specific prefix, not bucket-wide.
- `dynamodb:GetItem` / `Query` / `UpdateItem` scoped to a specific table ARN, with `dynamodb:LeadingKeys` condition for multi-tenant tables.
- `kms:Decrypt` + `kms:GenerateDataKey` on a specific key ARN, not `*`.
- `secretsmanager:GetSecretValue` on specific secret ARNs (support wildcard suffixes for versioned secrets).

## Resource scoping

```json
// BAD
"Resource": "*"

// BAD (still too broad for bucket contents)
"Resource": "arn:aws:s3:::my-bucket/*"

// GOOD — only the prefix the app owns
"Resource": "arn:aws:s3:::my-bucket/tenants/${aws:PrincipalTag/TenantId}/*"
```

Use `${aws:PrincipalTag/...}` in resource ARNs for tenant scoping — the principal's tag value substitutes at evaluation time.

For IAM roles (trust policies), scope the assuming principal:

```json
// BAD
"Principal": { "AWS": "*" }

// GOOD
"Principal": { "AWS": "arn:aws:iam::123456789012:role/DeployRole" }

// GOOD (GitHub OIDC)
"Principal": { "Federated": "arn:aws:iam::123:oidc-provider/token.actions.githubusercontent.com" },
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
  },
  "StringLike": {
    "token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:ref:refs/heads/main"
  }
}
```

The `sub` condition prevents any GitHub repo from assuming this role — only your repo on your branch.

## Condition keys worth knowing

| Condition | Use |
|---|---|
| `aws:SourceIp` | IP allowlist |
| `aws:SourceVpce` | Only from a specific VPC Endpoint |
| `aws:SourceVpc` | Only from a specific VPC |
| `aws:MultiFactorAuthPresent` | Require MFA |
| `aws:MultiFactorAuthAge` | MFA within last N seconds |
| `aws:PrincipalTag/*` | Tag-based access control |
| `aws:ResourceTag/*` | Resource tags — e.g., only touch resources with matching Owner tag |
| `aws:RequestTag/*` | Require specific tags on creation |
| `aws:SourceAccount` | Only from specific accounts |
| `aws:SecureTransport` | TLS-only (deny non-HTTPS S3 access) |
| `kms:ViaService` | KMS key only usable via specific services |

## The "no long-lived keys" rule

**IAM access keys (AKIA... + secret) are the worst artifact in AWS.**

- Leak by default (accidental commit, bash history, environment variables in logs).
- Long-lived until manually rotated.
- Permission-equivalent to the user they belong to.

Eliminate them:

- **Humans**: AWS SSO (IAM Identity Center) with IdP integration. Temporary creds via SSO.
- **Workloads on AWS**: EC2 instance profile, Lambda execution role, ECS task role, EKS IRSA, Fargate task role. All of these get temporary creds via STS.
- **Workloads off AWS (CI/CD, hybrid)**: OIDC federation. GitHub Actions, GitLab, Circle CI, Jenkins all support it. Configure an IAM role with a trust policy that accepts OIDC tokens from your CI provider; CI assumes the role per-job.

If you find an `AKIA...` long-lived key:

1. Find where it's used.
2. Replace with a role + STS pattern.
3. Delete the key.
4. Audit CloudTrail for unusual activity during the window it was live.

## Trust policy discipline

Trust policies on IAM roles define who can assume them. Treat them like firewall rules for privilege escalation.

- **`Principal` narrow** — specific user, role, or federated identity. Not `AWS:*`.
- **`sts:ExternalId`** for cross-account roles — prevents confused-deputy attacks when a third party assumes your role.
- **Session tags and conditions** to constrain further.

Cross-account assume-role with `ExternalId`:

```json
{
  "Effect": "Allow",
  "Principal": { "AWS": "arn:aws:iam::222222222222:role/ThirdPartyTool" },
  "Action": "sts:AssumeRole",
  "Condition": { "StringEquals": { "sts:ExternalId": "unique-random-value-shared-with-them" } }
}
```

The external-id is a shared secret; without it, another account that's been granted access can't assume the role on behalf of a confused deputy.

## Policy testing

- **`aws iam simulate-principal-policy`** — tell it an action + resource, it tells you allow/deny and why.
- **Access Analyzer** — tells you which policies grant access outside the account / org.
- **`iamlive`** — captures live AWS SDK calls, emits a minimal policy. Run your app against it to generate a starting policy.
- **`cfn-policy-validator` / `tflint` + IAM plugins** — lint IaC policies for wildcards, missing conditions.

## Common footguns

- **Using managed policies for prod.** AWS-managed policies like `PowerUserAccess` or `AmazonS3FullAccess` are broader than your app needs. Write custom.
- **Resource-based policy opens the door wider than identity policy closes it.** Both apply; the union of permissions is what the principal can do.
- **Forgetting to deny.** An explicit deny overrides any allow. Use it for guardrails (`"Action": "s3:*", "Effect": "Deny", "Condition": { "Bool": { "aws:SecureTransport": "false" } }`).
- **KMS policy missing → can't use the key.** KMS is locked down by key policy first; IAM is secondary. Default key policy must allow IAM (`"Principal": { "AWS": "arn:aws:iam::123:root" }`) or IAM grants do nothing.
- **Trust policy with a role ARN** — that role's creds can assume the target. If that role is deleted and recreated with the same name, it's a *different* AWS principal (different unique ID) and trust no longer works. Use the principal's unique ID if this matters; or accept the re-grant on recreation.
- **Overly permissive S3 bucket policies** paired with blocked public access — usually fine (Block Public Access wins) but the policy is misleading. Clean up either way.

## Review checklist

For any new/changed IAM policy:

- [ ] No `"Action": "*"`, `"service:*"`, or `"Resource": "*"` without a written comment justifying.
- [ ] `iam:PassRole` scoped to specific roles with `iam:PassedToService` condition.
- [ ] No `AWS: "*"` in trust policies.
- [ ] OIDC-based CI trust policies have `sub` claim conditions.
- [ ] Conditions include `aws:SecureTransport = true` for S3/DynamoDB data access.
- [ ] MFA required for sensitive actions (delete, rotate, offboard).
- [ ] Cross-account trust uses `sts:ExternalId`.
- [ ] KMS policies allow IAM role principals only, not everyone.
- [ ] No `AKIA...` access keys being created by this change.
