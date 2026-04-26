---
name: terraform-state-safety
description: Rules specific to protecting Terraform state and irreplaceable resources
source: stacks/terraform
alwaysApply: false
triggers: terraform, tf, state, backend, destroy, apply, prevent_destroy, lifecycle
globs: ["**/*.tf", "**/*.tfvars"]
---

# Terraform state safety

State is the most valuable artifact in a Terraform project. Losing it,
corrupting it, or silently diverging from it is how teams end up
re-creating production by hand.

## The backend block

Non-negotiable for any shared project:

```hcl
terraform {
  backend "s3" {
    bucket         = "myorg-tfstate-prod"
    key            = "networking/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "myorg-tfstate-locks"
  }
}
```

Checklist:

- **Remote backend** — S3, GCS, Azurerm, Terraform Cloud, HCP, Consul. Never local state for shared work.
- **Encryption at rest** — bucket encryption + SSE; KMS key for sensitive estates.
- **Versioning on the state bucket** — recover from accidental overwrite or bad apply.
- **Locking** — DynamoDB for S3 backend; built-in for TFC/HCP. Without locking, two applies race and corrupt state.
- **Access scoped** — the state bucket contains plaintext secrets pulled from secrets managers. Lock it down like production data.

## State hygiene

- **Separate state per environment.** `envs/dev/`, `envs/staging/`, `envs/prod/` — each with its own backend config.
- **Separate state per domain** when the estate grows. Network ≠ platform ≠ app. Smaller blast radius per apply.
- **Workspaces** (`terraform workspace`) are acceptable for trivial dev/staging/prod splits, but for real environments, separate backends are safer — they can't be confused at apply time.

## `prevent_destroy`

Apply to any resource whose destruction is irreversible or costly:

```hcl
resource "aws_db_instance" "main" {
  # ... config ...

  lifecycle {
    prevent_destroy = true
  }
}
```

Minimum set in any non-trivial project:

- Production databases (RDS, Cloud SQL, Cosmos DB, Dynamo tables with real data).
- S3/GCS/Blob buckets that hold data (not caches).
- DNS zones.
- KMS / CMK keys.
- Root IAM / OU / billing account resources.
- VPCs (re-creating causes cascading resource destruction).

`prevent_destroy` doesn't prevent `taint` or `state rm` — those bypass lifecycle. Pair with the hook layer (`block-destroy-apply.sh`) and human review.

## `create_before_destroy`

Use when a resource is referenced by running workloads and a gap causes outage:

```hcl
resource "aws_launch_template" "app" {
  # ...
  lifecycle {
    create_before_destroy = true
  }
}
```

- ALBs, ELBs behind DNS → yes.
- IAM roles used by running instances → yes.
- Security groups referenced by running resources → sometimes, with care (AWS has ordering quirks).
- Databases → no, this doesn't help; use blue-green migration for data-bearing resources.

Consequence: quota usage briefly doubles during apply. Size quotas accordingly.

## `ignore_changes`

Use sparingly; document every use:

```hcl
resource "aws_autoscaling_group" "app" {
  # ...
  lifecycle {
    # desired_capacity is managed by the autoscaling policy, not terraform
    ignore_changes = [desired_capacity]
  }
}
```

- Tags set by a Lambda/automation.
- Image IDs rotated by CI.
- Autoscaling desired_capacity.

Don't use `ignore_changes` to paper over drift — that hides legitimate problems.

## Planning for destroys

When a plan shows `-` (destroy) or `-/+` (replace):

- **Read every destroyed resource carefully.** Know what data lives there.
- **Replaces on data resources** (`aws_db_instance`, `aws_elasticache_*`, `aws_s3_object`) are especially dangerous — read the reason and the side effects.
- **If in doubt, split the change.** Apply the parts you understand; come back to the destroy-heavy part after confirmation.

## Apply discipline

- **Production:** plan → human review → `terraform apply tfplan` (saved plan only).
- **Staging:** plan → apply, with plan output visible in PR.
- **Dev:** relaxed, but still no `-auto-approve` on `destroy` or `state` mutations.
- **Never apply with local changes you haven't committed.** A broken laptop mid-apply leaves state ahead of source.

## State recovery

Practice this before you need it:

- Know where your state backup is (S3 versioning, TFC history, manual snapshots).
- Know how to restore: `aws s3api copy-object --copy-source ... --version-id ...`.
- Know the previous apply's plan output — cross-reference to understand what to roll back to.
- `terraform refresh` updates state from reality — useful to confirm what exists. Doesn't fix diverged state.

## Forbidden without explicit review

Hooks block these; this rule documents *why*:

- `terraform destroy` — wipes everything in state.
- `terraform apply -auto-approve` in any env with `prevent_destroy` resources.
- `terraform state rm` — removes tracking without touching reality. Reality no longer matches state.
- `terraform state mv` — renames in state. Safe in principle, easy to corrupt.
- `terraform taint` — marks for replacement. Use `-replace` on the next apply with review instead.
- `terraform force-unlock` — removes a lock that another process holds. If that process is still running, state will be concurrently modified. Almost always the wrong move.

## Audit

- **Read `terraform plan` output** as carefully as you'd read a production DB migration. Same level of consequence.
- **Compare plans across reruns** — if a PR's plan was reviewed Monday and applied Friday, re-plan first. Reality may have changed.
- **Failed applies need cleanup.** A partial apply leaves state inconsistent with reality; next plan will show confusing diffs. Investigate before proceeding.
