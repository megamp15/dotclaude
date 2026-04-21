# `for_each`, `count`, and dynamic blocks

The single worst class of Terraform bug is "I added a new thing and now
three other things want to be destroyed". Almost always caused by the wrong
iteration construct.

## The rule

- `for_each` over a **map or set of strings** — preferred.
- `count` **only** when the number is fixed or genuinely positional.
- Never `count = length(var.list)` on a user-provided list.

## Why `count` is dangerous

`count` indexes resources by integer position. Remove the first item and
every subsequent index shifts — Terraform sees this as "delete N, create
N-1".

```hcl
# ❌ BAD
resource "aws_instance" "web" {
  count = length(var.names)
  tags  = { Name = var.names[count.index] }
}
```

If `var.names = ["a", "b", "c"]` becomes `["b", "c"]`:

- `aws_instance.web[0]` (was "a") → wants to become "b" → destroy+recreate
- `aws_instance.web[1]` (was "b") → wants to become "c" → destroy+recreate
- `aws_instance.web[2]` (was "c") → destroy

One removal, three real mutations.

## `for_each` keys by identity

```hcl
# ✅ GOOD
resource "aws_instance" "web" {
  for_each = toset(var.names)
  tags     = { Name = each.key }
}
```

Remove "a" and Terraform destroys only `aws_instance.web["a"]`. Other
instances stay put.

## Map shapes

For more fields per instance:

```hcl
variable "instances" {
  type = map(object({
    instance_type = string
    az            = string
  }))
}

resource "aws_instance" "web" {
  for_each      = var.instances
  instance_type = each.value.instance_type
  availability_zone = each.value.az
  tags          = { Name = each.key }
}
```

Access: `each.key` (the map key), `each.value` (the map value).

## Key stability

`for_each` **requires** keys to be known at plan time. If you try:

```hcl
resource "aws_instance" "web" {
  for_each = { for i, s in aws_subnet.this : s.id => i }
  ...
}
```

…and `aws_subnet.this[*].id` isn't known yet, plan fails. Fix by keying on
something known at plan time (subnet name, not generated ID).

## Migrating `count` → `for_each`

```hcl
# Before
resource "aws_instance" "web" {
  count = length(var.names)
  tags  = { Name = var.names[count.index] }
}

# After
resource "aws_instance" "web" {
  for_each = toset(var.names)
  tags     = { Name = each.key }
}

# Add `moved` blocks to carry state forward
moved {
  from = aws_instance.web[0]
  to   = aws_instance.web["a"]
}
moved { from = aws_instance.web[1] to = aws_instance.web["b"] }
moved { from = aws_instance.web[2] to = aws_instance.web["c"] }
```

After `moved` blocks, `terraform plan` should show no infra changes — only
state addressing updates.

## When `count` is still the right tool

- Conditional single resource:

  ```hcl
  resource "aws_db_instance" "replica" {
    count = var.enable_replica ? 1 : 0
    ...
  }
  ```

  Then reference with `aws_db_instance.replica[0]` or use `one(resource...)`.

- Parallel arrays (rare, avoid if possible):

  ```hcl
  resource "aws_eip" "primary" {
    count = var.instance_count
  }
  resource "aws_instance" "primary" {
    count = var.instance_count
  }
  ```

  For more than ~3 parallel `count`s, reach for `for_each` with a richer
  map.

## `dynamic` blocks

For nested blocks (like `ingress` rules, `tags` that should iterate):

```hcl
resource "aws_security_group" "api" {
  name = "api"

  dynamic "ingress" {
    for_each = var.allowed_cidrs
    content {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "egress" {
    for_each = var.egress_rules
    content {
      from_port   = egress.value.from_port
      to_port     = egress.value.to_port
      protocol    = egress.value.protocol
      cidr_blocks = egress.value.cidr_blocks
    }
  }
}
```

Tips:

- The iterator variable defaults to the block name (`ingress.value`). Rename
  with `iterator = rule`.
- Overusing `dynamic` when the list is fixed is a readability tax. Write
  literal blocks when the set is stable.

## `for` expressions

Not to be confused with `for_each`. Produces a list or map from another:

```hcl
locals {
  ami_by_region = {
    for region, cfg in var.regions : region => cfg.ami_id
    if cfg.enabled
  }

  instance_list = [
    for k, cfg in var.instances :
    { name = k, type = cfg.instance_type }
  ]
}
```

Great for shaping inputs into what `for_each` wants.

## Module calls with `for_each`

```hcl
module "envs" {
  for_each = var.environments
  source   = "./modules/env"

  env_name = each.key
  vpc_cidr = each.value.vpc_cidr
}

output "env_vpc_ids" {
  value = { for k, m in module.envs : k => m.vpc_id }
}
```

Modules are first-class iteration targets — use them to stamp out parallel
environments or regions.

## Key collisions after refactors

Common trap: changing the keying scheme.

```hcl
# Was keyed by name
for_each = toset(var.names)    # keys: "a", "b"

# Now keyed by hash
for_each = { for n in var.names : md5(n) => n }   # keys: random hex
```

Every resource wants to be destroyed and recreated because the key
changed. Add `moved` blocks (one per instance, tedious but honest) or
don't change the keying scheme.

## Summary table

| Need | Use |
|---|---|
| 0 or 1 of a resource based on condition | `count = var.enabled ? 1 : 0` |
| N parallel copies of the same thing, input-driven | `for_each = toset(var.names)` |
| N copies with per-instance config | `for_each = var.instances` (map of objects) |
| Nested block iteration | `dynamic "<block>" { for_each = … }` |
| Shaping inputs | `for` expression in `locals` |
| Parallel modules | `for_each` on the module |
