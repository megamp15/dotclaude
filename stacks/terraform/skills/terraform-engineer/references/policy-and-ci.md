# Policy-as-code and CI

## Policy tools at a glance

| Tool | Scope | How |
|---|---|---|
| [Checkov](https://www.checkov.io/) | Static config checks, many cloud providers | Scans `.tf` source; 1000+ built-in policies |
| [tfsec](https://github.com/aquasecurity/tfsec) | Same space as Checkov, smaller | Now part of Trivy; still works standalone |
| [tflint](https://github.com/terraform-linters/tflint) | Deprecated args, unused vars, provider-specific lint | Run in local + CI |
| [OPA / Conftest](https://www.openpolicyagent.org/) | Write your own rules in Rego | Against plan JSON or HCL |
| [Sentinel](https://developer.hashicorp.com/sentinel) | Terraform Cloud / Enterprise only | HashiCorp's policy engine |

**Default stack**:

- `terraform fmt` + `terraform validate` in pre-commit.
- `tflint` + `Checkov` in PR CI (blocking on high severity).
- Infracost in PR CI (comment with cost delta; require approval above
  threshold).
- `terraform plan` in PR CI (posts plan output; apply blocked pending
  approval).
- `terraform apply` in `main` CI, gated on required reviewers.

## Checkov essentials

```bash
checkov -d . --framework terraform --output cli --output json --output-file-path console,checkov.json
```

Ignore specific rules:

```hcl
resource "aws_s3_bucket" "public" {
  bucket = "public-assets"
  # checkov:skip=CKV_AWS_21:Bucket intentionally has versioning disabled for ephemeral data
}
```

Rules to follow religiously:

- CKV_AWS_18 — S3 access logging
- CKV_AWS_20 — S3 ACL not public-read
- CKV_AWS_21 — S3 versioning enabled
- CKV_AWS_144 — S3 cross-region replication (for critical buckets)
- CKV_AWS_45 — Lambda env vars encrypted
- CKV2_AWS_12 — default VPC SG should restrict all traffic
- CKV_AWS_108 — IAM policies should not allow data exfiltration

## OPA / Conftest for bespoke rules

Write Rego policies against plan JSON:

```bash
terraform plan -out=tfplan.binary
terraform show -json tfplan.binary > plan.json
conftest test --policy ./policies plan.json
```

```rego
# policies/tags.rego
package main

required_tags := {"Owner", "CostCenter", "Environment"}

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_instance"
  resource.change.actions[_] == "create"
  missing := required_tags - {k | resource.change.after.tags[k]}
  count(missing) > 0
  msg := sprintf("%v missing required tags: %v", [resource.address, missing])
}
```

Use for rules specific to your org: tag compliance, allowed regions, bans
on specific instance classes, encryption requirements.

## CI pipeline — typical shape

### On pull request

```yaml
name: terraform-plan
on: [pull_request]

jobs:
  plan:
    runs-on: ubuntu-latest
    permissions:
      id-token: write     # for OIDC
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.9.0

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/tf-plan-readonly
          aws-region: us-east-1

      - run: terraform fmt -check -recursive
      - run: terraform init -input=false
      - run: terraform validate

      - uses: terraform-linters/setup-tflint@v4
      - run: tflint --recursive

      - uses: bridgecrewio/checkov-action@v12
        with:
          directory: .
          soft_fail: false
          framework: terraform

      - name: Plan
        run: terraform plan -no-color -input=false -out=tfplan.binary
      - name: Show plan
        run: terraform show -no-color tfplan.binary > plan.txt
      - uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const plan = fs.readFileSync('plan.txt', 'utf8').slice(0, 60000);
            github.rest.issues.createComment({
              ...context.repo,
              issue_number: context.issue.number,
              body: '```\n' + plan + '\n```'
            });
```

### On merge to `main`

```yaml
name: terraform-apply
on:
  push:
    branches: [main]

jobs:
  apply:
    runs-on: ubuntu-latest
    environment: production          # protected env → required reviewers
    permissions:
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with: { terraform_version: 1.9.0 }
      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::ACCOUNT:role/tf-apply-writer
          aws-region: us-east-1

      - run: terraform init -input=false
      - run: terraform apply -auto-approve -input=false
```

Points:

- **OIDC, not long-lived keys.** Short-lived federated creds per job.
- **Separate plan role (read-only) from apply role (write).** PR CI can't
  actually change things.
- **Protected environment** for apply jobs. GitHub won't run without
  reviewer approval.
- **Plan output as PR comment.** The review contract.

## Branching strategy

- `feature/*` — PR into `main`. Plan runs in CI.
- `main` — apply runs for every merged PR.
- **No** long-lived environment branches (`stage`, `prod`) — use states,
  not branches, for environment separation.

## Drift detection

Scheduled workflow:

```yaml
name: drift-detection
on:
  schedule:
    - cron: '0 6 * * *'      # daily 6am UTC

jobs:
  drift:
    strategy:
      matrix:
        state: [platform-prod-vpc, platform-prod-eks, apps-prod-api]
    steps:
      - uses: actions/checkout@v4
      - run: |
          cd infra/${{ matrix.state }}
          terraform init -input=false
          terraform plan -detailed-exitcode -input=false || echo "DRIFT=$?" >> $GITHUB_ENV
      - if: env.DRIFT == '2'
        run: |
          # Alert: file an issue, ping Slack, etc.
          gh issue create --title "Drift in ${{ matrix.state }}" \
                          --body "$(cat plan.txt)"
```

## Secret handling

- **Secrets enter `terraform` via env vars or data sources**, never as
  literals in `.tf` or committed `.tfvars`.
- `var.db_password` with `sensitive = true` only redacts from CLI output;
  the value still sits in state. If the secret is sensitive, store it in
  Secrets Manager / Parameter Store and reference it at runtime from the
  app, not from Terraform.
- If Terraform must manage a secret (DB password at create time):
  ```hcl
  resource "random_password" "db" { length = 32 }
  resource "aws_secretsmanager_secret_version" "db" {
    secret_id     = aws_secretsmanager_secret.db.id
    secret_string = random_password.db.result
  }
  ```
  The password lives in state but never in git.

## Approval chains (Terraform Cloud / OpenTofu Cloud)

When you outgrow GitHub's environment protections:

- Run stages: plan → approval → apply.
- Policy integration (Sentinel / OPA) evaluated between plan and apply.
- Role-based access: who can queue, who can approve, who can override.

Worth the cost when you have > ~3 teams running infra concurrently.
