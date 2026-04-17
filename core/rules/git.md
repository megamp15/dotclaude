---
name: git
description: Universal git, commit message, branch, and PR conventions
source: core
alwaysApply: true
---

# Git

## Branches

- `main` (or `master`) is protected — never push directly, never force-push.
- Short-lived feature branches off `main`: `feat/add-invoice-export`, `fix/rate-limit-reset`, `refactor/extract-client`, `chore/upgrade-pytest`.
- Prefixes: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `hotfix`.
- Delete branches after merge.

## Commits

- Subject line: imperative mood, ≤72 chars, no trailing period.
  - Good: `Add retry logic to NASA client`
  - Bad: `added retry` / `adding retries` / `This adds retries.`
- Separate subject from body with a blank line.
- Body wraps at 72 chars. Explain *why*, not *what* — the diff shows what.
- Reference issues: `Fixes #123`, `Refs #456`, `Closes ORG-42`.
- One logical change per commit. If you find yourself listing changes with "and", it's two commits.

### Good commit body

```
Add retry logic to NASA client

The NEO endpoint intermittently returns 502 during NASA's overnight
window (roughly 02:00–04:00 UTC). Three retries with exponential
backoff recovers without impacting user-perceived latency.

Fixes #214.
```

## Conventional Commits (optional, project-configurable)

If the project uses Conventional Commits:

- `feat(scope): description` for new features
- `fix(scope): description` for bug fixes
- `refactor(scope): description` for refactors
- `docs(scope): description` for docs-only changes
- `BREAKING CHANGE: ...` footer or `!` after scope for breaking changes

## What not to commit

- Secrets, credentials, PII.
- Build artifacts, logs, editor swap files.
- Commented-out code.
- `console.log`, `print`, `pdb.set_trace`, `debugger;` left in.
- Large binaries without LFS.
- Auto-generated files that are reproducible from source (unless the project explicitly commits them — e.g., lockfiles).

## Staging

- Review `git diff --cached` before every commit. Read every line.
- `git add -p` (or equivalent) when staging — don't blanket-add untracked dirs.
- Never `git add .` without knowing what's untracked.

## Rebase vs merge

- Rebase feature branches onto `main` before opening a PR (linear history).
- Squash-merge short feature branches; merge-commit long ones with meaningful sub-commits.
- Never rewrite shared history (published branches others may have fetched).

## PRs

- Title: same rules as commit subject.
- Body includes: *what changed*, *why*, *how to test*, *risk*, *rollback plan* if non-trivial.
- Keep PRs under ~400 lines diff when possible. Larger PRs get fewer real reviews.
- Draft PRs for WIP; mark ready when truly ready.
- Re-request review after non-trivial changes.

## Co-authorship

- Pair/mob work: add `Co-authored-by: Name <email>` trailers.
- AI-assisted work: follow your org's disclosure policy. Default in this setup is to NOT add AI co-authorship lines unless requested.

## Forbidden

- `git push --force` on shared branches.
- `git reset --hard` without a backup (stash or branch).
- `git clean -fdx` without reviewing what's about to die.
- Committing during an interrupted rebase without finishing it.
- Amending a pushed commit.
