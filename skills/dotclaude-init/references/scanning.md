# Scanning rules

Read-only detection. Never mutates files. Runs before any question is asked.

## Stack detection

Stacks are **layered**, not mutually exclusive. A project can legitimately be
`python + docker + terraform + github-actions` and should get rules from all
four. Pick the language stack as primary; layer infra stacks on top.

### Language stacks

| Evidence | Stack |
|---|---|
| `pyproject.toml`, `requirements.txt`, `setup.py`, or `*.py` at root | `python` |
| `package.json` with `typescript` / `@types/*` in deps, or `tsconfig.json` | `node-ts` |
| `package.json` without TS | `node-ts` (still recommended — TS rules degrade gracefully to JS) |
| `go.mod` | `go` |
| `Cargo.toml` | `rust` |
| `Gemfile` | `ruby` |
| `pom.xml` or `build.gradle*` | `jvm` |
| `*.csproj`, `*.sln`, `global.json` | `dotnet` |

### Infrastructure / platform stacks (additive)

| Evidence | Stack |
|---|---|
| `Dockerfile`, `*.Dockerfile`, `docker-compose*.y*ml`, `compose*.y*ml` | `docker` |
| `*.tf`, `*.tfvars`, `.terraform.lock.hcl` | `terraform` |
| `.github/workflows/*.y*ml` | `github-actions` |
| `kind: Deployment`, `kind: Service`, `kind: StatefulSet`, `apiVersion: apps/v1` in yaml; or `kustomization.yaml`, `Chart.yaml`, `helmfile.yaml` | `kubernetes` |
| `aws-cdk.json`, `cdk.json`, `serverless.yml`, `samconfig.toml`, `aws_*` resources in `*.tf`, `*.aws/` dir, `AWS_*` env vars in config | `aws` |

Apply every matching infra stack — their rules don't conflict with the
language stack's.

### Frontend stacks (additive to node-ts; can also layer on any backend stack)

| Evidence | Stack |
|---|---|
| `"react"` in `package.json` deps | `react` |
| `"@angular/core"` in `package.json`, `angular.json` | `angular` |
| `hx-get` / `hx-post` / `hx-target` attrs in templates; `htmx.org` in deps or a CDN `<script>` | `htmx-alpine` |
| `x-data` / `x-show` / `x-on:` attrs; `alpinejs` in deps or CDN `<script>` | `htmx-alpine` |
| `"reflex"` in `requirements.txt` / `pyproject.toml`, `rxconfig.py`, `import reflex as rx` | `reflex` |

### ML / inference stacks (additive to python)

| Evidence | Stack |
|---|---|
| `torch` or `pytorch-lightning` or `accelerate` in deps; `import torch` | `pytorch` |
| `vllm` in deps; `vllm serve` in Dockerfiles / compose; `ollama/ollama` image; `OLLAMA_*` env vars; `ollama pull` in scripts | `vllm-ollama` |

## Framework detection (within a stack)

Grep the source files for import/config patterns:

**Python**
- `from fastapi`, `FastAPI(` → `fastapi`
- `from django`, `INSTALLED_APPS` → `django`
- `from flask` → `flask`
- `import pandas`, `pd.DataFrame` → `data`
- `import torch`, `from transformers` → `ml`

**Node**
- `"next"` in package.json → `next`
- `"react"` in package.json → `react` (also triggers `stacks/react`)
- `"@angular/core"` in package.json → `angular` (also triggers `stacks/angular`)
- `"@nestjs/core"` → `nestjs`
- `"express"` → `express`

**.NET**
- `Microsoft.AspNetCore.*` in `*.csproj` → `aspnetcore`
- `Microsoft.EntityFrameworkCore` → `efcore`
- `*.Api.csproj` with `Program.cs` using `WebApplication.CreateBuilder` → `minimal-api`

Frameworks drive which optional skills and MCPs get proposed in the interview.

## Domain hub auto-loading

Domain hubs (`core/skills/<hub>/SKILL.md`) are loaded on-demand via
Claude's skill discovery, not pre-installed into every `.claude/`. The
init skill copies **all** of `core/skills/` into `.claude/skills/`
unconditionally; Claude's own skill mechanism decides which to activate
based on the user's current task and the skill's `triggers:` list.

However, init can **proactively suggest** hubs based on scan findings:

| Signal | Proactively mention hub |
|---|---|
| `stacks/pytorch` or `stacks/vllm-ollama` matched; or `import vllm`, `OLLAMA_*`, `gguf`, `awq`, `gptq` in repo | `llm-serving` |
| `stacks/kubernetes` matched; or Proxmox / Talos / k3s evidence; or homelab-ish topology (`helmfile.yaml`, `flux-system/`, `argocd/`) | `homelab-infra` |

"Proactively mention" means print a one-line note in the init summary
("Heads up: the `llm-serving` domain skill is available and will
auto-activate for questions about model serving, quantization, VRAM
sizing, etc."). Does not change what gets installed.

## External service detection

Grep repo for known hostnames and env var names. Map each hit to a candidate MCP:

| Hostname / env var | Candidate MCP |
|---|---|
| `api.github.com`, `GITHUB_TOKEN`, `.github/` dir | github (opt-in) |
| `POSTGRES_URL`, `DATABASE_URL`, `psycopg`, `asyncpg` | postgres |
| `sqlite3`, `*.db`, `*.sqlite` | sqlite |
| `REDIS_URL` | redis |
| `api.anthropic.com`, `ANTHROPIC_API_KEY` | (none — docs via context7) |
| `api.openai.com`, `OPENAI_API_KEY` | (none — docs via context7) |
| `*.sentry.io`, `SENTRY_DSN` | sentry (free tier works) |
| `hooks.slack.com`, `SLACK_TOKEN` | slack (if a free MCP exists) |
| Other `api.*.com` hosts | propose context7 for their docs |

## MCP recommendation rules

Beyond per-service matches above, these broader triggers propose MCPs:

| Signal | Propose |
|---|---|
| Any recognized framework (Next, Django, FastAPI, Rails, Spring, etc.) | `context7` (opt-in) — for current framework docs |
| Project is a frontend/webapp (React/Vue/Svelte/Next + a dev server) | `chrome-devtools` (opt-in) — heavy context, so off by default |
| Project has a `.github/` directory or GitHub remote | `github` (opt-in) — requires PAT |
| Project uses local Postgres for dev (detected above) | `postgres` (opt-in) — stack-scoped |

The always-on core MCPs (`filesystem`, `fetch`, `git`, `memory`,
`sequential-thinking`, `time`) go in every project regardless of stack.
See `core/mcp/README.md` for the full list.

## Existing `.claude/` detection

If `.claude/` already exists:

1. Read every file. Files with `source:` frontmatter came from core/stack.
2. Files without `source:` are **project-owned** — never touched by init.
3. Diff stack/core files against what the current `DOTCLAUDE_HOME` would produce. Classify:
   - **Missing** — file in current core/stack, not in target → propose adding.
   - **Outdated** — target file's body differs from source → propose updating (show diff).
   - **Orphaned** — target has `source:` pointing at something no longer in dotclaude → propose deleting, confirm first.
4. If the target's `.claude/rules/project.md` exists, read it and load prior interview answers. Do not re-ask; only prompt "anything changed?" at the end.

## Output shape

Return a structured findings object the interview phase consumes:

```json
{
  "stacks": ["python"],
  "frameworks": ["fastapi"],
  "external_services": ["postgres", "github"],
  "candidate_mcps": ["postgres", "github"],
  "existing_claude": {
    "status": "present",
    "missing": ["rules/python-style.md"],
    "outdated": [],
    "orphaned": [],
    "prior_answers": { "owners": "@pmahir", "rate_limit": "1000/hr" }
  }
}
```
