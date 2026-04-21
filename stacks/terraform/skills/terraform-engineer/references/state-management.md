# State management

State is the source of truth for what Terraform *thinks* it owns. Keep it
small, backed up, and versioned.

## Remote backend — always

Never commit `terraform.tfstate` to git. Minimum requirements:

- **Remote storage** (S3, GCS, Azure blob, Terraform Cloud, OpenTofu Cloud).
- **Locking** — prevents two applies racing each other.
- **Encryption at rest** — the file contains secrets, always.
- **Versioning** — roll back to a prior state if you corrupt the current one.

### AWS S3 + DynamoDB

```hcl
terraform {
  backend "s3" {
    bucket         = "mycorp-tfstate-prod"
    key            = "platform/vpc/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tfstate-locks"
    encrypt        = true
  }
}
```

Keys by team / system / environment, not by date. The key is how you'll find
this state later.

Bootstrap: the S3 bucket + DynamoDB table are themselves infra — manage them
in a separate bootstrap root (often with local state the first time, then
migrated).

### GCS

```hcl
terraform {
  backend "gcs" {
    bucket = "mycorp-tfstate-prod"
    prefix = "platform/vpc"
  }
}
```

GCS has native object-level locking; no separate table needed.

### Terraform Cloud / OpenTofu Cloud

```hcl
cloud {
  organization = "mycorp"
  workspaces { name = "platform-prod-vpc" }
}
```

Pros: UI, run queue, policy integration, team permissions.
Cons: pricing, vendor relationship.

## One state per (env × system)

| State file | Content |
|---|---|
| `platform-dev-vpc` | VPC, subnets, route tables for dev |
| `platform-prod-vpc` | Same, for prod |
| `apps-dev-api` | API service resources for dev |
| `apps-prod-api` | Same, for prod |

Never one giant state. Failure modes:

- Refactoring one system's resources plans against unrelated systems.
- State file grows to MB, every `plan` takes minutes.
- Locking means the whole org is blocked during one apply.

## Reading between states

Use `terraform_remote_state` as a read-only lookup:

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "mycorp-tfstate-prod"
    key    = "platform/vpc/terraform.tfstate"
    region = "us-east-1"
  }
}

resource "aws_security_group" "api" {
  vpc_id = data.terraform_remote_state.vpc.outputs.vpc_id
}
```

Consumers only see the producer's `outputs.tf`. Treat these as stable
contracts — renaming an output breaks consumers downstream.

## Importing existing resources

When a resource was created by hand / console / other tool:

```bash
# Option A: import block (1.5+, preferred — reviewable)
cat >> imports.tf <<'HCL'
import {
  to = aws_s3_bucket.legacy
  id = "my-legacy-bucket"
}
resource "aws_s3_bucket" "legacy" {
  bucket = "my-legacy-bucket"
  # Fill in arguments to match current state
}
HCL

terraform plan          # shows nothing to change if HCL matches
terraform apply         # performs the import, no infra changes

# Then remove the import block

# Option B: terraform import CLI (older style)
terraform import aws_s3_bucket.legacy my-legacy-bucket
# Then hand-author the resource block
```

Process:

1. Write the `resource` block matching the existing config.
2. Add an `import { to = …, id = … }` block.
3. `terraform plan` — expect "Will import" + no changes.
4. Discrepancies? Fix the HCL until plan is clean. Never accept a plan that
   wants to destroy/recreate the import target.
5. `terraform apply` performs the import.
6. Remove the `import` block; keep the `resource` block.

## `moved` blocks — refactor without destruction

When you rename or restructure without changing actual resources:

```hcl
moved {
  from = aws_instance.web
  to   = aws_instance.api
}

moved {
  from = aws_instance.api
  to   = module.api.aws_instance.server
}
```

Terraform updates state to match the new address, no infra changes.

Cases:

- Renaming a resource (`aws_instance.web` → `aws_instance.api`).
- Moving a resource into a module.
- Refactoring `count` → `for_each`.
- Splitting a file.

Always prefer `moved` over `state mv` — it's reviewable in PRs.

## `terraform state` — for the last-resort cases

```bash
terraform state list
terraform state show <addr>

# Rename address (prefer `moved` block instead)
terraform state mv aws_instance.web aws_instance.api

# Remove from state without destroying actual resource
terraform state rm aws_instance.legacy

# Pull / push raw state (for deep surgery)
terraform state pull > state.json
# ... edit (NEVER casually)
terraform state push state.json
```

Rules:

- **Backup before any `state` operation.** `terraform state pull > backup.tfstate`.
- **Never hand-edit `.tfstate` unless the house is on fire.**
- **After surgery, `terraform plan` must produce zero diff.** If it doesn't,
  you didn't finish.

## Splitting state

Goal: one state file becomes two.

```bash
# In the source state
terraform state list
terraform state mv 'module.apps.module.api' '../new-root/terraform.tfstate' # requires -state / -state-out flags in older versions, use `terraform state rm` + re-import in newer
```

Modern flow:

1. Create the new root module referencing the resources.
2. In the old root, `terraform state rm <addrs>` to unmanage (infra stays
   alive).
3. In the new root, `import` blocks to adopt the resources.
4. Plan both roots to verify zero diff.

## Merging state

Flip of splitting:

1. In source root, `terraform state pull > source.tfstate`.
2. In target root, `terraform state pull > target.tfstate`.
3. For each resource: `terraform state mv -state=source.tfstate -state-out=target.tfstate <src_addr> <tgt_addr>`.
4. Push target state.
5. In the source root, remove the HCL + `terraform state rm` anything left.
6. Plan both roots, zero diff.

## Recovering a broken state

Most common cause: `apply` partially failed, state doesn't match reality.

- **Simplest fix**: `terraform refresh` (updates state to match cloud),
  then `terraform plan` to see what's missing / extra.
- **Resource drifted**: adjust HCL to match, or `apply` to reset to the
  desired config.
- **Resource destroyed outside TF**: `terraform apply` will recreate it,
  or `terraform state rm` if you want to abandon it.
- **State file corrupted**: restore from backend versioning
  (S3 versioning / TFC history) to last known good.

## Locks stuck

DynamoDB lock row stuck from a cancelled apply:

```bash
terraform force-unlock <LOCK_ID>
```

`LOCK_ID` is printed in the error message. Verify nobody else is actually
applying first.

## State file size

If your state file is >10MB, you've probably got one of:

- Too many resources in one state (split).
- A provider that stores large bodies in state (content hashes, large JSON
  policies) — use `jsondecode(file(...))` and source the big blob from disk
  instead.

## Access control

- Separate IAM roles per environment. A dev role can't read prod state.
- Apply from CI, not from laptops. Laptops hold long-lived creds and are
  every attacker's favorite target.
- Encrypt the backend bucket with a customer-managed KMS key scoped to the
  apply role.
