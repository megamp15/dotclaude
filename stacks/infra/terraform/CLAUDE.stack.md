<!-- source: stacks/terraform -->

# Terraform conventions

Applies to any project containing `.tf` files. These rules are tool- and
cloud-agnostic; cloud-specific (`stacks/aws`, `stacks/gcp`) refine them.

## The blast-radius mindset

Terraform is not application code. A typo here isn't a test failure —
it's data loss, a dropped RDS instance, a deleted VPC. Every change runs
under an operational assumption: **"if this applies incorrectly, what is
destroyed?"**

Default posture: high-consequence, low-velocity, plan-before-apply, never
auto-apply in production without review.

## State

- **State is the source of truth about reality.** Losing or corrupting it is the worst-case failure mode; plan to never do that.
- **Remote state, always** (S3+DynamoDB, GCS, Terraform Cloud, HCP). Local state is dev-only.
- **State locking, always.** Concurrent applies without locking corrupt state. S3 backend requires a DynamoDB lock table; don't skip it.
- **Per-environment state.** `dev.tfstate`, `staging.tfstate`, `prod.tfstate` — separate files. A shared state across envs is a ticking time bomb.
- **Per-concern state** for large estates. Networking state separate from compute separate from data. Smaller blast radius per apply.
- **Never edit state by hand.** Use `terraform state mv`, `terraform state rm`, `terraform import`. Hand-editing JSON is how you explain an outage to your manager.

## Module layout

- **`modules/` for reusable building blocks**; `environments/` (or `stacks/`) for concrete deployments that consume modules.
- Each module has: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, `README.md`.
- **Pin module sources** — exact version or commit. Never `?ref=main`.
- **Modules should be stateless** in the sense that they declare resources; they don't fetch runtime data they shouldn't. Data sources within modules are fine; calling out to a REST API inside a module is a smell.

## Providers

- **Pin provider versions** in `versions.tf`:
  ```hcl
  terraform {
    required_version = ">= 1.6.0, < 2.0.0"
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "~> 5.40"
      }
    }
  }
  ```
- **Lock file (`.terraform.lock.hcl`) is committed.** Reproducible provider versions across runs.
- **Provider aliases** for multi-region / multi-account: `provider "aws" { alias = "us_east_1", region = "us-east-1" }`.

## Variables

- **Typed.** `type = string`, `type = list(object({...}))`. Untyped variables accept anything; you'll find out what in prod.
- **Default-less for required values.** If a variable must be set, no default. Makes missing values fail at plan, not at apply.
- **Validation blocks** for constraints:
  ```hcl
  variable "environment" {
    type = string
    validation {
      condition     = contains(["dev", "staging", "prod"], var.environment)
      error_message = "environment must be dev, staging, or prod."
    }
  }
  ```
- **Sensitive variables** marked `sensitive = true`. Hides them from plan output. Still don't put secrets in `tfvars` files committed to Git — use env vars or a secrets manager.

## Outputs

- **Describe in the `description` field.** Other stacks will consume these.
- **Mark sensitive outputs** `sensitive = true`.
- **Stable output names.** Renaming an output breaks consumers.

## Resources

### Lifecycle

- **`prevent_destroy = true`** on irreplaceable resources: databases, data buckets, DNS zones, KMS keys.
  ```hcl
  lifecycle {
    prevent_destroy = true
  }
  ```
- **`create_before_destroy`** for resources where a gap would cause an outage (ELBs, IAM roles used by running workloads).
- **`ignore_changes`** for fields managed out-of-band (tags by a Lambda, image ID by CI). Document why.

### Naming

- **Logical names are what you call them in HCL (`aws_db_instance.main`);** physical names are the cloud-side identifier. Keep both meaningful.
- **Include environment in physical names** (`myapp-prod-db`) so cross-account visibility is unambiguous.
- **Use `random_id` / `random_pet` for globally-unique names** (S3 buckets, IAM global resources) rather than `myapp-bucket-v2`.

### Data sources

- Use `data` blocks to reference things Terraform doesn't own (an existing VPC, an external DNS zone). Prefer data sources to hard-coded IDs — IDs drift.
- Data sources still run queries; cache what you can, don't fetch in a loop.

## `plan` discipline

- **Every apply is preceded by a plan in the same session**, reviewed by a human (or the author, at minimum).
- **Save the plan, apply the plan** for production:
  ```bash
  terraform plan -out=tfplan
  # review
  terraform apply tfplan
  ```
  Prevents drift between "what I reviewed" and "what ran."
- **Never apply with `-auto-approve`** in any environment where `destroy` is visible in the plan. Interactive approval is the safety net; don't disable it.
- **Read destroys carefully.** `-/+` means "replace" — destroy + recreate. For an RDS instance or an EBS volume, that's data loss.

## Forbidden without review

- `terraform destroy` against anything non-ephemeral.
- `terraform state rm` / `terraform state mv` — these change state directly.
- `-replace=...` on a data-bearing resource.
- Deleting or renaming a module a live environment uses.
- Any plan with `prevent_destroy` resources showing `destroy`.

## Secrets

- **Never in `.tf` files.** Use a secrets manager (AWS Secrets Manager, HashiCorp Vault, SSM Parameter Store) and reference via data source.
- **Never in `.tfvars` committed to Git.** Use `.tfvars` for non-secret config; secrets come from env (`TF_VAR_*`) or a secrets source.
- **State contains resolved values.** A secret pulled from a data source ends up in state in plaintext. Encrypt state at rest and restrict who can read it.

## CI/CD

- **Plan in PR, apply after merge** — the standard pattern. Plan output visible in the PR for review.
- **Apply from a bastion/CI role**, not from developer machines, for production.
- **Fail the PR on drift** — `terraform plan` showing changes for a commit that didn't touch tf means someone changed things out-of-band. Investigate.

## Format, validate, lint

- `terraform fmt` — auto-format. Hook this on save.
- `terraform validate` — catches HCL errors and type mismatches before plan.
- `tflint` — linter; catches deprecated syntax, bad patterns, unused variables.
- `checkov` or `tfsec` — security scans; useful, but tune rules so they're not ignored.

## Common smells

| Smell | Why |
|---|---|
| `provider` without version constraint | Provider upgrades change behavior silently |
| `?ref=main` on a module source | Non-reproducible |
| `resource "aws_s3_bucket" "data" {}` no `prevent_destroy` | One bad `tf destroy` erases the data |
| Secrets in `.tfvars` or `locals` | In state forever, in git forever |
| `count` where `for_each` is clearer | `count` reorders on changes; `for_each` preserves identity |
| `-auto-approve` in CI for prod | No human review on destructive ops |
| Shared state across envs | Dev mistake applies to prod |
| `terraform apply` with no prior `plan` | No review of what's about to change |
