# Terraform module design

## When something should be a module

A module is worth making when:

- It will be **used more than once** (across envs, regions, teams).
- It represents a **unit of ownership** (a "component" the platform team owns).
- Its internals can be **hidden** behind a small input surface.

It is **not** worth making when:

- It's used once and wraps a single resource. You've added indirection for no
  gain.
- The inputs outnumber the actual resource arguments.

## Module anatomy

```
modules/
└── vpc/
    ├── README.md          # contract + examples; generated with terraform-docs
    ├── main.tf            # resources
    ├── variables.tf       # inputs — typed, described, validated
    ├── outputs.tf         # outputs — everything consumers need
    ├── versions.tf        # required_version + required_providers
    └── examples/
        └── basic/
            └── main.tf    # a working consumer, used for tests
```

## Variables: typed and disciplined

```hcl
variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be /16 or larger."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR."
  }
}

variable "subnet_config" {
  description = "Map of subnet name to config."
  type = map(object({
    cidr_block        = string
    availability_zone = string
    public            = bool
  }))
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
```

Rules:

- **Always** set `type`. `any` is a smell.
- **Always** set `description` — it shows up in `terraform-docs` and IDEs.
- Add `validation` for anything non-obvious (CIDR shape, enum values,
  length bounds).
- Defaults only for truly optional inputs; required inputs have no default.

## Outputs: everything the consumer needs

```hcl
output "vpc_id" {
  description = "The ID of the VPC."
  value       = aws_vpc.this.id
}

output "subnet_ids_by_name" {
  description = "Map of subnet name to subnet ID."
  value       = { for k, s in aws_subnet.this : k => s.id }
}

output "private_route_table_id" {
  description = "Route table for private subnets; consumers attach routes."
  value       = aws_route_table.private.id
  sensitive   = false
}
```

Rules:

- Expose **IDs, ARNs, and shapes** consumers need to wire up dependents.
- Don't expose internal implementation (the hash used in name suffixes, etc.).
- `sensitive = true` for anything secret-like.

## Providers live in the root

A reusable module must not declare a `provider` block. It declares what
providers it *needs*:

```hcl
# versions.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

The root module supplies the provider. For aliased providers (e.g.,
cross-region resources):

```hcl
# in the module
terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.0"
      configuration_aliases = [aws.primary, aws.replica]
    }
  }
}

# in the root module
module "db" {
  source = "./modules/db"
  providers = {
    aws.primary = aws.us_east_1
    aws.replica = aws.us_west_2
  }
}
```

## Composition patterns

**Small, composable modules** beat one monolithic "everything" module.

- `vpc/` (network)
- `eks/` (cluster, needs vpc outputs)
- `rds/` (databases)
- `app/<service>/` (app-specific: task def, service, alarms)

Root modules wire them together. The root is where the opinions about your
*environment shape* live; modules stay generic.

**Don't cross-reference modules inside modules.** Root composes; modules
stay leaves.

## Module versioning

Tag releases. Consume by exact ref.

```hcl
module "vpc" {
  source  = "git::https://github.com/megamp15/tf-modules.git//vpc?ref=v1.4.0"
  # or via registry:
  # source  = "megamp15/vpc/aws"
  # version = "1.4.0"
}
```

Follow semver:

- **Patch** — bug fixes, no new inputs.
- **Minor** — new optional inputs, new outputs, no breaking change.
- **Major** — removed or renamed input/output, changed default, anything that
  could trigger a plan diff for existing consumers.

Deprecations:

- Add new input, mark old as deprecated in `description`.
- Keep both for one minor version.
- Remove in next major.

## Documentation with `terraform-docs`

```bash
terraform-docs markdown table --output-file README.md --output-mode inject modules/vpc/
```

Generates the Inputs/Outputs tables consumers actually read. Run in CI; fail
if the generated docs drift from the source.

## Terragrunt fit

Terragrunt wraps Terraform with:

- DRY `backend` and `provider` config (each root gets its own state, one
  config).
- Dependency management between root modules.
- Keeping prod / stage / dev configs in parallel tree structure.

When it helps:

- ≥ 3 environments × ≥ 3 systems (nine or more state files).
- You want to enforce "each root module has its own state" at the file
  system level.

When it's overkill:

- A handful of root modules. The extra indirection isn't worth it.

## Testing

- **`terraform validate`** — syntax + references. Run in CI.
- **`tflint`** — provider-specific checks (deprecated args, unused vars).
- **Examples-as-tests** — each module has at least one `examples/` root
  that `terraform init && terraform validate` proves works.
- **Terratest** (Go) or **`terraform test`** (1.6+) — run `apply`/`destroy`
  against a sandbox to prove real end-to-end shape. Slow but high
  confidence.

## Registry conventions (if publishing)

- Naming: `terraform-<provider>-<name>` (e.g., `terraform-aws-vpc`).
- Registry structure: repo root is the primary module; `modules/*` subtree
  for related submodules.
- Include `LICENSE`, `CHANGELOG.md`, and `examples/`.
- Use GitHub Actions to tag + publish on release.
