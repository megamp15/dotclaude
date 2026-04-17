---
name: github-mcp
description: Use the GitHub MCP server for issues, PRs, search, and repo operations. Prefer over shelling out to `gh` for bulk or search-heavy tasks.
triggers: github mcp, gh issue, pull request, repository, octokit, github api, list issues, search code
source: core/mcp
---

# GitHub MCP

Official GitHub MCP server. Free to use; requires a personal access token
in the `GITHUB_PERSONAL_ACCESS_TOKEN` env var.

## When to prefer MCP over `gh` CLI

- Bulk / search-heavy operations (listing 50 open issues with filters)
- Cross-repo queries against an org
- Structured responses you want to feed directly into another tool call without parsing
- Programmatic filtering by labels, milestones, reviewers

## When to prefer `gh` CLI

- One-off read of a specific PR or issue (`gh pr view 123`)
- Creating a PR with a HEREDOC body — `gh` formats multiline bodies better
- Scripted pipelines where shell output is natural
- Commenting on a PR during the same session where a commit was just pushed

## Auth

Token needs at minimum:
- `repo` scope for private repositories
- `read:org` scope for organization data

Store the token in 1Password, `~/.secrets/github-mcp`, or a keyring — never
commit it to repo config. Sourced via shell init (`export GITHUB_PERSONAL_ACCESS_TOKEN=...`).

## Common pitfalls

- **Rate limit**: 5000 req/hour for authenticated users. The MCP doesn't batch —
  avoid unbounded loops over repos; use search endpoints with filters instead.
- **No caching**: repeated identical queries are repeated requests.
- **Timeline API is paginated**: a single issue with 200 comments requires multiple calls.
- **Draft PRs**: some endpoints silently exclude drafts unless you pass `draft: true` explicitly.
