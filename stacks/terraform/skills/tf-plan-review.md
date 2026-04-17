---
name: tf-plan-review
description: Read a terraform plan and report what's safe, what's risky, and what to question before applying
source: stacks/terraform
---

# Terraform plan review

Use when: a `terraform plan` has been produced and needs human-level
review before apply. This skill reads the plan like a reviewer, not a
compiler.

## Input

The plan text (from `terraform plan` or `terraform show tfplan`). If not
given, ask for it. Don't review an unseen plan from memory.

## Output shape

```
## Plan summary

- Changes: N add, N change, N destroy, N replace
- Scope: <modules / resources touched, at a glance>
- Risk: LOW / MEDIUM / HIGH
- Blocker: yes / no

## High-risk changes

(empty if none; otherwise a list with resource + why)

## Safe changes

(brief: "N security groups adjusted — all additions; M IAM role tags updated")

## Questions before apply

(concrete things to check/confirm; link to file:line where helpful)

## Recommendation

Apply / apply-with-caveats / split-and-re-review / don't-apply-yet
```

Be honest about risk. Don't pad with "looks good overall" if you haven't
actually verified.

## What to flag as HIGH risk

- Any `-` (destroy) line on a **data-bearing** resource: databases, caches with persistent state, data buckets, DNS zones, KMS keys, IAM root entities.
- Any `-/+` (replace) on a data-bearing resource.
- Any change to a `prevent_destroy` resource — it shouldn't be possible; if it is, someone removed the guard.
- Changes to authentication / authorization: IAM policies, security groups going wider (more permissive), public access enablement.
- Changes to the Terraform backend config — easy to lose state this way.
- Provider version jumps (implicit via plan output, explicit via `versions.tf` change).
- Replaces on resources with immutable identifiers that other resources reference (subnet IDs, VPC IDs).

## What's typically LOW risk

- Tags-only updates (noise, but rarely dangerous).
- Autoscaling desired count changes.
- New resources added (creation without replacement).
- Module output changes that aren't consumed elsewhere.

## Things to actually check

### For each destroy / replace

- **Is this resource protected by `prevent_destroy`?** If so, the plan shouldn't even reach apply; something is off.
- **Does the replace preserve data?** For most stateful resources, the answer is no.
- **Is there a `lifecycle` block that should have `create_before_destroy`?** Gap could cause outage.
- **Is the reason for replace sensible?** Plan often gives a "because X changed" — check that change is intentional.

### For IAM / security changes

- **Does the permission broaden or narrow?** Broader access should be explained.
- **Are new principals trusted?** Added roles, added federated providers — who's now trusted to assume.
- **Public access toggles** (S3 public access block, security group 0.0.0.0/0, RDS `publicly_accessible`) — always call out.

### For network changes

- **CIDR changes on a VPC/subnet** often force dependent resource changes (instances in those subnets). Trace the cascade.
- **Route table / NAT / IGW** changes affect traffic paths; easy to break prod connectivity.

### For provider version bumps

- Read the provider changelog for major-version or multi-minor jumps. Schema changes produce silent replaces.
- Look for resources whose `schema version` changed.

## Questions to ask (if unclear from the plan alone)

- "What's the pre-apply state vs plan's assumed baseline?" (Was a `-refresh=false` used?)
- "When was this plan generated?" (Old plans may not reflect reality.)
- "Is this the full plan or a `-target=...` subset?" (Targeted applies hide dependencies.)
- "Which workspace / backend does this apply to?" (Confirm env.)

## When to recommend `don't-apply-yet`

- Any unexplained destroy on a data resource.
- Plan output doesn't match what the PR description says changed (strong signal of drift or targeted-apply confusion).
- Provider schema version change with no module version bump in the repo.
- State file recently modified out-of-band (check the backend).

## When to recommend `split-and-re-review`

- Plan is large (100+ resources) and mixes risk levels. Apply the safe portion, re-plan, review the risky portion fresh.
- Plan contains both infra *and* a destructive state move. Separate commits.

## Format of findings

```
### [HIGH] aws_db_instance.main — replace

**Plan line:** ~ `replace because: storage_type changed`
**Why it matters:** Replacing an RDS instance destroys all data in the current instance.
**Check:** Is there an explicit data migration plan? Is this a zero-data environment?
**Suggested:** Do not apply. Either revert `storage_type` or plan a blue-green.
```

Keep findings one-screen-each, concrete, actionable.

## Anti-patterns

- Rubber-stamp approval ("plan LGTM"). If the plan has 400 resources changing, someone has to actually read it.
- Approving based on "CI passed." CI ran the plan; it didn't review it.
- Ignoring destroys because they "were expected." Always verify.
- Reviewing a plan days after it was generated. Generate a fresh one if there's been any delay.
