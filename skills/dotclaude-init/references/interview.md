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

### Continuity layer (special handling)

Three MCPs are part of the dotclaude **continuity layer** and get
default-ON treatment, not default-OFF like the others. All three get a
**three-way question** — wire only, wire and install now, or skip —
rather than the usual yes/no, because installing them is a one-time
machine-wide step the user may want init to handle while they're
already paying attention.

- **`brain-mcp`** — cross-agent persistent memory. Phrasing depends on
  whether the binary is already on PATH:

  **If `continuity.brain_mcp_installed` is true:**

  > "Wire brain-mcp for cross-agent memory? (Default: yes. Already
  > installed on this machine — just adds the wiring.)"
  >
  > Options: `[ ] yes (default)` · `[ ] no, skip`

  **If `continuity.brain_mcp_installed` is false:**

  > "Wire brain-mcp for cross-agent memory? (Default: wire-only.
  > Free, MIT, 100% local. Lets you switch between Claude Code,
  > Cursor, Codex without losing context. The binary isn't installed
  > yet — I can run `pipx install brain-mcp && brain-mcp setup` for
  > you now if you want.)"
  >
  > Options:
  > - `[x] wire only — I'll install brain-mcp myself later (default)`
  > - `[ ] wire AND install now — run pipx install + brain-mcp setup with my confirmation`
  > - `[ ] skip both wiring and install`

  The `brain-mcp setup` command is the recommended global path —
  once run, brain-mcp is wired into every agent on the machine. The
  project's `.mcp.json` entry is for project-isolated brains, which
  is rare. Mention this distinction inline if the user asks.

- **`graphify`** — multi-modal codebase knowledge graph. Same three-way
  pattern, gated on repo size:

  **If `continuity.graphify_installed` is true:**

  > "Wire graphify for a queryable code graph? (Default: yes for
  > non-trivial repos.)"
  >
  > Options: `[ ] yes (default for >30 files / recognized framework)` · `[ ] no, skip`

  **If `continuity.graphify_installed` is false AND repo is non-trivial:**

  > "Wire graphify for a queryable code graph? (Default: wire-only.
  > Free, MIT, local-first. Tree-sitter + Leiden clustering.
  > Worth it for repos big enough to need 'where do I even start'
  > questions. Not installed yet — I can run
  > `pip install graphifyy && graphify install` for you now.)"
  >
  > Options:
  > - `[x] wire only — install graphifyy myself later (default)`
  > - `[ ] wire AND install now — run pip install + graphify install with my confirmation`
  > - `[ ] skip both wiring and install`

  For **trivial** repos (<30 files, no framework), default to
  "skip both" but still offer the question — leave the option visible.

- **`code-review-graph`** — incremental review-time code graph. Pairs
  with graphify (graphify = exploration, CRG = review). Same three-way
  pattern, gated on **active** development:

  **If `continuity.crg_installed` is true:**

  > "Wire code-review-graph for blast-radius analysis on PRs and edits?
  > (Default: yes for active non-trivial repos.)"
  >
  > Options: `[ ] yes (default for >30 files / commits in last 30d)` · `[ ] no, skip`

  **If `continuity.crg_installed` is false AND repo is non-trivial AND active:**

  > "Wire code-review-graph for blast-radius analysis on PRs and edits?
  > (Default: wire-only. Free, MIT, local-first, SQLite. Tree-sitter
  > graph that auto-updates in <2s on every save/commit. 28 MCP tools
  > including `detect_changes_tool` and `get_impact_radius_tool`. Best
  > for daily review loops; greenfield doesn't need it yet. Not
  > installed yet — I can run
  > `pip install code-review-graph && code-review-graph install` for
  > you now.)"
  >
  > Options:
  > - `[x] wire only — install code-review-graph myself later (default)`
  > - `[ ] wire AND install now — run pip install + code-review-graph install with my confirmation`
  > - `[ ] skip both wiring and install`

  For **greenfield** repos (≤3 commits) or trivial repos (<30 files),
  default to "skip both" — there's nothing meaningful to review yet.
  CRG can be wired later by re-running init once the repo is active.

  **CRG vs graphify in the same project.** Both can coexist with no
  conflict. The skills explicitly route different question shapes to
  the right tool. If the user really wants only one, prefer:
  - **graphify** for "I'm onboarding / exploring an unfamiliar repo" first.
  - **CRG** for "I'm actively shipping changes on a known repo" first.

**Confirmation discipline if "wire AND install now" is chosen:**
init does NOT run the install commands silently. Even after the user
picks the install option, init prints the exact commands it's about
to run and asks one final yes/no per command before invoking shell.
Anything that fails is non-fatal — print the error, suggest the
manual command, and continue with the rest of init. The wiring still
goes in either way.

Don't gate the rest of init on these answers. The continuity layer
degrades gracefully — if brain-mcp isn't installed, the conductor
brief says so and the agent skips that step.

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
