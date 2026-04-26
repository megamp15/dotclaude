---
source: stacks/github-actions
---

# Stack: GitHub Actions

CI/CD workflow conventions. Layers on `core/`. Additive with any runtime
stack. The workflows in `.github/workflows/` are code; they deserve the
same review discipline as application code.

## Default principles

- **Reproducible.** Same commit + same inputs → same outcome. Pin actions by SHA (not tag), pin runner images, pin tool versions.
- **Fast.** Cache aggressively, split into independent jobs, skip unchanged paths.
- **Secure.** Least-privilege `GITHUB_TOKEN`, OIDC instead of long-lived cloud keys, review third-party actions before adoption.
- **Observable.** Jobs named well, logs grouped, failure surfaced at the PR UI.
- **Cheap to change.** Reusable workflows + composite actions for shared logic.

## File layout

```
.github/
├── workflows/
│   ├── ci.yml                # PR/push — lint, typecheck, test, build
│   ├── release.yml           # tag-push — build + publish + release notes
│   ├── deploy-staging.yml
│   ├── deploy-production.yml  # manual approval / tag-triggered
│   ├── security.yml          # CodeQL, dependency review, secret scan on schedule
│   └── pr-title.yml          # lint PR title against conventional commits
├── actions/                   # local composite actions
│   └── setup-toolchain/
│       └── action.yml
├── CODEOWNERS
├── PULL_REQUEST_TEMPLATE.md
└── dependabot.yml
```

## Triggering — be explicit, be narrow

```yaml
on:
  push:
    branches: [main]
    paths-ignore: ['**.md', 'docs/**']
  pull_request:
    branches: [main]
    paths:
      - 'src/**'
      - 'package.json'
      - '.github/workflows/ci.yml'
```

- **Path filters** avoid CI runs on pure-docs PRs.
- **Branch filters** on `push` and `pull_request` — otherwise fork PRs double-run.
- **`workflow_dispatch`** for manual triggers — define typed `inputs`.
- **`schedule`** for periodic scans (deps, security) — don't tie to the main pipeline.

## Concurrency — prevent wasted runs

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
```

Cancels the previous run on the same branch when a new commit lands. Saves runner minutes and gives faster feedback.

For **deploys**, use `cancel-in-progress: false` and a named group — two deploys to production shouldn't race, and cancelling mid-deploy is usually worse than queuing:

```yaml
concurrency:
  group: deploy-production
  cancel-in-progress: false
```

## Permissions — least privilege per job

Default workflow token is **read-only** if you set it. Grant scopes per job.

```yaml
permissions: {}         # deny all at workflow level

jobs:
  test:
    permissions:
      contents: read    # clone repo
  deploy:
    permissions:
      id-token: write   # OIDC to cloud
      contents: read
  release:
    permissions:
      contents: write   # create release, tag
      issues: write
```

Never leave `permissions: write-all` or unspecified for anything but a throwaway repo.

## Action pinning — SHAs, not tags

```yaml
# BAD — tag can move (even @v4); supply chain risk
- uses: actions/checkout@v4

# GOOD — immutable SHA
- uses: actions/checkout@b4ffde65f46336ab88eb53be808477a3936bae11 # v4.1.1
```

For first-party (`actions/*`) and very trusted actions, tags are usually acceptable. For third-party actions: **always pin to SHA**. Dependabot can update them and track the version comment.

**Never run a third-party action you haven't skim-reviewed.** `run` commands in someone else's action execute with your repo's secrets and `GITHUB_TOKEN`.

## OIDC — no long-lived cloud keys

Cloud deploys should use OIDC tokens, not stored access keys:

```yaml
jobs:
  deploy:
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: aws-actions/configure-aws-credentials@<sha>
        with:
          role-to-assume: arn:aws:iam::123:role/DeployRole
          aws-region: us-east-1
      - run: aws s3 sync ./dist s3://my-bucket/
```

The cloud-side role trust policy validates:
- The OIDC issuer (`token.actions.githubusercontent.com`).
- The subject (`sub`) — restricts which repo + branch can assume the role:
  ```
  repo:myorg/myrepo:ref:refs/heads/main
  ```
  (Never grant to `repo:myorg/*:ref:*` — any repo on any branch.)

Same pattern for GCP (Workload Identity Federation), Azure (federated credentials), HashiCorp Cloud (workload identity).

## Secrets — the short list of rules

- **Environment secrets** for per-environment secrets (`staging`, `production`) with environment protection rules (reviewers, branch filters).
- **Repository secrets** for shared credentials.
- **Organization secrets** for multi-repo shared credentials with repo allowlist.
- **Never `echo $SECRET`** — GitHub redacts literal matches but transforms (base64, slicing) slip through.
- **Never pass secrets into third-party actions** unless you've reviewed them at the pinned SHA.
- **Rotate if logged.** If a secret appears in a log, treat it as compromised.

## Caching — where the real speedup is

```yaml
- uses: actions/setup-node@<sha>
  with:
    node-version: '20'
    cache: 'pnpm'          # built-in for npm/yarn/pnpm

- uses: actions/cache@<sha>
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements*.txt') }}
    restore-keys: |
      ${{ runner.os }}-pip-
```

Key must include a hash of the input that would invalidate the cache (lockfile). Without that, you cache stale deps forever.

- **Language toolchains** (setup-node, setup-python, setup-go) have built-in caching — use it.
- **Build output caches** (Rust target/, Gradle caches, Nx build caches) can cut multi-minute builds to seconds.
- **Docker layer cache** via `docker/build-push-action` + `cache-from: type=gha`.

## Job composition

- **Parallelize.** Independent jobs in separate `jobs:`. GitHub runs them concurrently.
- **Matrix** for platform / version fan-out. Use `fail-fast: false` for test matrices (you want to see all failures, not bail on first).
- **`needs:`** to serialize where necessary.
- **`if:`** for conditional jobs (e.g., deploy only on main).
- **Reusable workflows** (`uses: ./.github/workflows/_test.yml`) for logic shared across workflows in the same repo.
- **Composite actions** (`uses: ./.github/actions/setup`) for shared step sequences.

## Environments

```yaml
jobs:
  deploy-prod:
    environment:
      name: production
      url: https://app.example.com
    steps: ...
```

Environments unlock:

- **Required reviewers** — human approval before the job runs.
- **Wait timer** — mandatory delay before deploy (canary window).
- **Deployment branches** — only `main` can target `production`.
- **Environment secrets** — different values per environment.
- **Deployment history** in the repo UI.

Use environments for anything that touches real infra. Free on public repos; available on private with Pro/Enterprise plans.

## Status reporting

- **Named jobs** in the required-status-check list (branch protection).
- **Annotations** — use `echo "::error file=...,line=...::message"` or let a linter emit SARIF for inline PR comments.
- **Logs grouped** — `echo "::group::Install"` … `echo "::endgroup::"` for readable logs.
- **Step summaries** — write Markdown to `$GITHUB_STEP_SUMMARY` for rich PR-attached reports.

## Pull-request hygiene

- **`pull_request`** trigger doesn't have write access to the repo and doesn't receive secrets (for fork PRs). Use `pull_request_target` only when you understand the risks — it runs *in the context of the base branch* with secrets, which can be exploited by malicious PR code.
- **`pull_request_target` + checkout of PR code + `run: npm install`** = supply-chain disaster. Never do this.
- **Dependency review action** on every PR — fails the check on new high/critical CVEs added.

## Dependabot

`.github/dependabot.yml`:

- **Ecosystems** you actually use (`npm`, `pip`, `docker`, `github-actions`, `gomod`).
- **Group updates** where possible: all patch-level updates in one PR, not dozens.
- **Schedule weekly** (daily is noisy).
- **Security updates always on.**

## Common footguns

- **Using `${{ github.event.pull_request.title }}` in `run:`** — injection. PR title can contain shell metacharacters. Use env vars: `env: TITLE: ${{ ... }}` then `"$TITLE"` in script.
- **`pull_request_target` without caveats.** See above.
- **Unpinned third-party actions.** Supply-chain compromise.
- **Long-running workflows with no `timeout-minutes:`.** Stuck jobs burn minutes for hours.
- **Caching `node_modules` instead of `~/.npm`.** Usually slower to restore + verify than a fresh install.
- **Matrix without `fail-fast: false` on test jobs.** You miss failures on other matrix cells.
- **Running tests in the same job as the build that publishes a Docker image.** Split — tests can fail and not waste the build.

## Do not

- Do not use `pull_request_target` with checkout of PR code without explicit security review.
- Do not leave `permissions:` unset or `write-all`.
- Do not use long-lived cloud credentials stored as secrets — prefer OIDC.
- Do not `echo` secrets (even transformed).
- Do not depend on third-party actions pinned by mutable tag.
- Do not put deployment logic in the same workflow file as PR checks — split.
- Do not disable branch protection to unblock a broken workflow; fix the workflow.
