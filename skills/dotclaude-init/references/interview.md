# Interview — the invisibles

Only ask what code can't reveal. Batch questions with `AskUserQuestion`.

## Phase 1 — confirm the scan

Present the scan findings as a checklist. One AskUserQuestion call, multi-select:

> "I detected: Python 3.11, FastAPI, Postgres, hits GitHub API. Uncheck anything wrong."

If the user unchecks something, drop it silently — don't argue.

## Phase 2 — MCP opt-ins

For each candidate MCP from the scan, ask once:

> "Enable GitHub MCP? (free, needs a PAT in `GITHUB_PERSONAL_ACCESS_TOKEN`)"

Batch as multi-select with a short note on credentials for each.

## Phase 3 — always-ask invisibles

These can't be detected. Ask every time (show prior answer if re-running):

1. **Owners.** Who reviews PRs? Who's the domain expert? GitHub handles.
2. **Public API surface.** Which symbols/files are the contract? (Library projects only — skip for apps.)
3. **Sensitive paths.** Directories or file patterns where edits need extra care? (Migrations, billing, auth.)

## Phase 4 — conditional invisibles

Ask only if the scan surfaced the signal:

| Scan signal | Question |
|---|---|
| External API detected | What's the rate limit? Auth env var name? Secrets source (1Password, Vault, .env)? |
| Database detected | Migration policy — who runs them, how? |
| Multiple services | Request-tracing convention? (correlation IDs, OTel, nothing) |
| Tests exist | Any test that must stay green for release? Coverage expectation? |
| CI config | Which checks block merge? |
| Lockfile pins old versions | Reason for pins? (grep for comments nearby; only ask if none found) |

## How to phrase

- **Prefer multi-choice over open-ended.** Faster for user, cleaner to parse.
- **Offer "skip / fill in later"** for every question. Incomplete answers are fine — the project file can be edited later.
- **Cap at ~5 questions total.** More than that means the scan is too weak — improve the scan, don't ask more.

## Never ask

- Anything detectable from file tree or imports.
- Tooling versions — read lockfiles.
- Personal style opinions already covered in stack conventions.
- Confirmation of obvious choices ("should we use `uv`? yes it's already in pyproject.toml").

## Answer placement

After all questions answered, write:

- **Bullet-style rules** (rate limits, sensitive paths, public API list) → `.claude/rules/project.md`
- **Narrative context** (project description, API overview, owners) → `.claude/CLAUDE.md` "Project context" section
- **Raw answers** (for idempotency on re-run) → `.claude/.dotclaude-interview.json` (gitignored)

Never write credentials, API keys, or PATs into any file. If the user pastes one, warn and redact.
