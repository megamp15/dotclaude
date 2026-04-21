---
name: terraform-engineer
description: Deep Terraform 1.5+ / OpenTofu expertise — module design, state management (remote backends, state surgery, locking, import), lifecycle rules, for_each vs. count, workspaces vs. directories, policy-as-code (Sentinel / OPA / Checkov), provider mechanics, and zero-downtime migrations. Extends the rules in `stacks/terraform/rules/state-safety.md`.
source: stacks/terraform
triggers: /terraform-engineer, terraform, opentofu, tofu, HCL, module design, remote state, state surgery, terraform import, for_each vs count, terragrunt, checkov, tfsec, opa, sentinel, provider versioning, lifecycle ignore_changes, moved block, terraform plan diff
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/terraform-engineer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# terraform-engineer

Production-grade Terraform / OpenTofu expertise. Activates when the question
is about module shape, state safety, migrations, or provider quirks — not the
first-time "how do I write HCL" questions.

> **See also:**
>
> - `stacks/terraform/CLAUDE.stack.md` — baseline conventions
> - `stacks/terraform/rules/state-safety.md` — enforceable rules
> - `core/skills/cloud-architect/` — when the question is really "what should
>   this topology be"
> - `core/skills/architecture-designer/` — when making architectural decisions
>   about modules vs. monolith infra

## When to use this skill

- Designing a module that will be consumed by many environments / teams.
- Planning a state migration (`moved`, `import`, split, merge) without
  recreating resources.
- Debugging a `terraform plan` that wants to destroy things it shouldn't.
- Choosing between `count`, `for_each`, and module instances.
- Adopting policy-as-code (Checkov, tfsec, OPA, Sentinel).
- Upgrading provider / Terraform major versions.

## References (load on demand)

- [`references/module-design.md`](references/module-design.md) — the module
  contract, inputs/outputs discipline, composability, versioning, registry
  conventions, Terragrunt fit.
- [`references/state-management.md`](references/state-management.md) — remote
  backends, locking, workspaces, `terraform import`, `moved` blocks, `state
  mv/rm`, rescuing broken state, split/merge.
- [`references/for-each-and-count.md`](references/for-each-and-count.md) —
  when to use which, the `for_each` key-stability rule, maps vs. sets, dynamic
  blocks, key collisions after refactors.
- [`references/lifecycle-and-migrations.md`](references/lifecycle-and-migrations.md)
  — `lifecycle` meta-arguments (`create_before_destroy`, `prevent_destroy`,
  `ignore_changes`, `replace_triggered_by`), zero-downtime resource
  replacement, taint/untaint (avoid), `moved` blocks.
- [`references/policy-and-ci.md`](references/policy-and-ci.md) — Checkov,
  tfsec, tflint, OPA/Rego, Sentinel, CI pipelines (plan on PR, apply on
  merge), drift detection, cost estimation with Infracost.

## Core workflow

1. **Read `plan` line by line.** The + / ~ / -/+ symbols are the contract;
   don't `apply` until you understand every non-obvious line.
2. **State is truth.** Don't edit `terraform.tfstate` by hand. Use `state mv`,
   `state rm`, `import`, `moved` blocks.
3. **Small blast radius.** Each state file is a failure domain — split by
   environment at minimum, often by system-within-environment.
4. **Pin everything.** Terraform version, provider versions, module versions.
   No `latest`, no unconstrained `~>`, no implicit upgrades.
5. **Automate safely.** Plan on PR, apply on merge, with approvals for prod.
   Every apply produces an artifact (plan output) you can audit later.

## Defaults

| Question | Default |
|---|---|
| Terraform vs. OpenTofu | OpenTofu for new projects (open-source, governance clear); Terraform if already in place |
| Version pin style | `~> 5.x` for providers, exact for Terraform (`required_version = "1.9.0"`) |
| Backend | S3 + DynamoDB locking (AWS), GCS (GCP), Azure blob + state locking, or Terraform Cloud / OpenTofu Cloud |
| State layout | One state per (environment × system). Never one monolithic state |
| Resource iteration | `for_each` over a map, **not** `count`; makes keys stable |
| Secret inputs | `sensitive = true` on var + output; never commit `terraform.tfvars` with secrets |
| Module source | Registry tag / git tag pinned by SHA, not `main` |
| Drift detection | Scheduled `terraform plan` in CI, alert on non-empty diff |
| Cost visibility | Infracost in PRs |
| Security scanning | Checkov or tfsec in CI, blocking on high-severity |

## Anti-patterns

- **`terraform apply` on `main` without review.** Everything goes through a
  reviewed plan.
- **One giant state file.** The first outage you can't recover from cheaply
  will teach you this; better to learn it first.
- **`count = length(...)` over a dynamic list.** When an element is removed,
  every subsequent resource is destroyed and recreated. Use `for_each`.
- **`provider` block inside a reusable module.** Providers belong in the root
  module; modules receive them implicitly. Exception: aliased providers passed
  through.
- **`taint` / `untaint`** as a workflow tool. Use `terraform apply -replace
  '<addr>'` or a `replace_triggered_by` lifecycle argument.
- **Editing state by hand.** Ever.
- **Mixing Terraform-managed and non-Terraform-managed resources in the same
  blast radius.** Eventually someone clicks the console and drifts silently.
- **Uncommitted `.terraform.lock.hcl`.** That lockfile is the provider
  equivalent of `package-lock.json` — commit it.
- **Unpinned module sources.** `source = "..."` with `ref = "main"` means
  your infra changes when you don't expect.

## Output format

For module-design questions:

```
Inputs (vars):
  <typed var list with descriptions>

Outputs:
  <outputs with what consumers do with them>

Contract:
  <one paragraph: "given X inputs, this module guarantees Y">

Known limits:
  <things the module won't do — region constraints, prereqs>
```

For state surgery:

```
Current state:
  <resource addresses now>

Target state:
  <resource addresses after>

Steps (all reversible where possible):
  1. <plan to confirm>
  2. <moved {} block or state mv>
  3. <plan — should be empty>
  4. <apply if any real change>

Rollback:
  <how to undo if step 3 shows unexpected diff>
```
