# Diff scoping rules

Make sure each agent sees **the right diff** — not more, not less.

## Sources (in priority order)

1. `gh pr diff <n>` — use when the user gives a PR number or URL.
2. `git diff --cached` — use for `staged` or no-argument invocations.
3. `git diff <base>...HEAD` — use when the user names a branch; base defaults to `main` (or `master`, fall back if `main` doesn't exist).
4. `git diff <base>...HEAD -- <path>` — use when a specific file is named.

## Scope cap

- Diffs over ~1500 lines: warn the user, ask whether to proceed or narrow scope.
- Diffs that touch >30 files: same. Large PRs get shallow reviews.
- Lockfiles and generated files: exclude from the reviewed diff. Use `:(exclude)package-lock.json ':(exclude)*.lock'`.

## Context the agents need

Along with the diff, agents should receive:

- The PR title and description (if any).
- The list of changed files (helps the router decide which agents to run).
- A brief note on what was *not* touched (e.g., "tests in auth/ unchanged — worth noting").

## Signals for agent routing

| Signal | Agent to include |
|---|---|
| Any code change | `code-reviewer` |
| Changes in `auth/`, `login`, `session`, `token`, `password`, `permission`, `acl`, `csrf`, `cors` | `security-reviewer` |
| Changes in `deps`, `requirements`, `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod` | `security-reviewer` (dep audit) |
| SQL queries added/changed, ORM usage, loops over `list`/`queryset`, async code | `performance-reviewer` |
| Frontend — React/Vue/Svelte/Angular components, especially in lists and forms | `performance-reviewer` |
| `.md` files, docstrings on exported symbols, public README | `doc-reviewer` |
| New modules, new top-level directories, new external integrations, new DB tables | `architect` |

## What's out of scope for pr-review

- Merging the PR.
- Replying on GitHub (that's a separate `gh pr review` action, only on explicit request).
- Rewriting the code on the author's behalf.
- Running tests (that's what CI is for — but note if tests are missing).
