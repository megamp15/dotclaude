# Lifecycle rules and zero-downtime migrations

## The `lifecycle` meta-argument

```hcl
resource "aws_instance" "api" {
  # ...
  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
    ignore_changes        = [tags["LastApplied"]]
    replace_triggered_by  = [aws_launch_template.api.latest_version]
  }
}
```

### `create_before_destroy`

When a resource needs to be replaced (type change, name change, etc.), the
default is **destroy then create**. For anything user-facing this means
downtime.

```hcl
lifecycle {
  create_before_destroy = true
}
```

- Requires the resource name / ID to differ — LB target groups, security
  groups, S3 buckets often collide on name. Plan carefully.
- Good for: launch templates, ASGs (though ASG has its own "new instances
  before terminating old" mechanism), most infra that can coexist during
  replacement.
- Bad for: resources that can't coexist (unique PK, DNS name already
  assigned).

### `prevent_destroy`

```hcl
lifecycle {
  prevent_destroy = true
}
```

Block any destroy, even intentional. Use for:

- Production databases.
- S3 buckets holding user data.
- Anything that would take > 1 hour to restore.

`terraform destroy` on a state containing this resource will fail. Override
by removing the flag (commit, plan, apply) — making removal a deliberate
two-commit process.

### `ignore_changes`

```hcl
lifecycle {
  ignore_changes = [
    tags["LastAppliedAt"],
    user_data,                     # managed by an external tool
  ]
}
```

Terraform won't report these as drift. Use for:

- Tags added by external automation (cost allocation, ASG tagging).
- `user_data` rendered from another system (e.g. Packer output referenced by
  hash).
- Autoscaler-managed fields (`desired_capacity` on ASG).

Don't use it to paper over drift you should fix.

### `replace_triggered_by`

```hcl
lifecycle {
  replace_triggered_by = [aws_launch_template.api.latest_version]
}
```

Recreate this resource when something else changes. Common for:

- Forcing an instance refresh when the launch template updates.
- Recreating a Lambda when its zip hash changes (usually
  `source_code_hash` handles this directly).

Prefer a specific trigger over a timestamp — the former is deterministic,
the latter means "replace every apply".

## Zero-downtime replacement patterns

### Instance replacement behind an ASG

Use an ASG with `instance_refresh`:

```hcl
resource "aws_autoscaling_group" "api" {
  # ...
  launch_template {
    id      = aws_launch_template.api.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 75
      instance_warmup        = 60
    }
    triggers = ["tag"]
  }

  lifecycle {
    ignore_changes = [desired_capacity]
  }
}
```

### Blue/green databases

Migrating `db.m5` → `db.m6` instance class:

Option A — in place:

```hcl
resource "aws_db_instance" "main" {
  instance_class    = "db.m6g.xlarge"   # was m5.xlarge
  apply_immediately = false              # apply at next maintenance
}
```

RDS handles the swap with a short failover window.

Option B — blue/green with `aws_rds_cluster` + `aws_rds_cluster_endpoint`:
spin up the new cluster, replicate, cut endpoint. Beyond Terraform's
happy path — use AWS's native blue/green deployment and import results.

### ALB target-group swaps

`lifecycle { create_before_destroy = true }` on the TG + `name_prefix`
instead of `name` so the replacement doesn't collide.

```hcl
resource "aws_lb_target_group" "api" {
  name_prefix = "api-"
  # ...
  lifecycle { create_before_destroy = true }
}
```

## `moved` blocks (covered in state-management.md)

Use `moved` when the **resource address** changes but the underlying
infrastructure doesn't. Never destroy + recreate for a rename.

## Dependency graph surgery

Terraform infers dependencies from references. If you need a dependency
that isn't reference-visible:

```hcl
resource "null_resource" "wait_for_policy" {
  depends_on = [aws_iam_role_policy.api]
}

resource "aws_lambda_function" "api" {
  # ...
  depends_on = [null_resource.wait_for_policy]
}
```

Rule: avoid `depends_on` where a real reference would work. Explicit
dependencies drift from reality over time.

## Avoiding `taint` and `untaint`

`terraform taint` is deprecated in favor of:

```bash
terraform apply -replace='aws_instance.api'
```

It's a flag on `plan`/`apply`, gets reviewed in the plan output, and doesn't
leave state in a half-modified state if you cancel.

## Version upgrades

### Terraform core

```hcl
terraform {
  required_version = "~> 1.9.0"
}
```

Check the [upgrade guide](https://developer.hashicorp.com/terraform/language/v1.x-compatibility-promises)
for each major bump. Typical path:

1. Upgrade local TF version.
2. Commit `.terraform.lock.hcl` updates.
3. Run `plan` in a dev state — deal with any new warnings.
4. Roll to other environments.

### Provider versions

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

Major provider bumps (4 → 5) can rename attributes, change defaults,
deprecate resources. Read the changelog before bumping. Pin to a specific
minor version in shared modules so consumers upgrade on their schedule.

### `.terraform.lock.hcl`

Commit this. It's your `package-lock.json` — pins provider plugin versions
+ checksums. `terraform init -upgrade` to refresh; PR the resulting diff.

## Input validation for safer modules

```hcl
variable "instance_count" {
  type    = number
  default = 1
  validation {
    condition     = var.instance_count > 0 && var.instance_count <= 100
    error_message = "instance_count must be between 1 and 100."
  }
}
```

Catches misconfigs at `plan`, before any apply touches reality.

## Drift detection in CI

Scheduled job (daily) that runs `terraform plan` against each state:

```bash
terraform init -input=false -backend-config=...
terraform plan -detailed-exitcode -input=false -lock=false
# Exit 0 = no changes
# Exit 1 = error
# Exit 2 = changes detected (drift)
```

Alert on exit code 2. Drift not caused by your PRs means someone clicked a
button.

## Cost visibility

Run Infracost in PR:

```yaml
- uses: infracost/actions/setup@v3
  with: { api-key: ${{ secrets.INFRACOST_API_KEY }} }
- run: |
    infracost breakdown --path=. --format=json --out-file=/tmp/base.json
    # baseline vs. HEAD → posted as PR comment
```

Changes that cost > $X trigger an approval. Catches accidental `db.r6.8xlarge`
before it ships.
