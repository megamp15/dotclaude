# Ported Skills

Some dotclaude skills are adapted from
[Jeffallan/claude-skills](https://github.com/Jeffallan/claude-skills).
They are rewritten in dotclaude voice and scope, with provenance tracked in
frontmatter.

Convention:
[../core/conventions/ported-skills.md](../core/conventions/ported-skills.md)

| Location | Skill | Origin |
|---|---|---|
| `core/skills/` | `architect` | `architecture-designer`, `cloud-architect`, `microservices-architect`, `api-designer`, `graphql-architect` |
| `core/skills/` | `the-fool` | `the-fool` |
| `core/skills/` | `feature-forge` | `feature-forge` |
| `core/skills/` | `spec-miner` | `spec-miner` |
| `core/skills/` | `code-documenter` | `code-documenter` |
| `core/skills/` | `fullstack-guardian` | `fullstack-guardian` |
| `core/skills/` | `postgres-pro` | `postgres-pro` |
| `core/skills/` | `sql-pro` | `sql-pro` |
| `core/skills/` | `sre-engineer` | `sre-engineer` |
| `core/skills/` | `monitoring-expert` | `monitoring-expert` |
| `core/skills/` | `testing` | `test-master` plus dotclaude `tdd` and `test-writer` |
| `core/skills/` | `playwright-expert` | `playwright-expert` |
| `core/skills/` | `security` | `secure-code-guardian`, `security-reviewer` |
| `core/skills/` | `rag-architect` | `rag-architect` |
| `core/skills/` | `ml-pipeline` | `ml-pipeline` |
| `core/skills/` | `fine-tuning-expert` | `fine-tuning-expert` |
| `core/skills/` | `prompt-engineer` | `prompt-engineer` |
| `core/skills/` | `websocket-engineer` | `websocket-engineer` |
| `core/skills/` | `chaos-engineer` | `chaos-engineer` |
| `core/skills/` | `debugging` | `debugging-wizard` plus dotclaude `debug-fix` |
| `core/skills/` | `legacy-modernizer` | `legacy-modernizer` |
| `stacks/lang/python/skills/` | `python-pro` | `python-pro` |
| `stacks/lang/node-ts/skills/` | `typescript-pro` | `typescript-pro` |
| `stacks/infra/terraform/skills/` | `terraform-engineer` | `terraform-engineer` |
| `stacks/infra/kubernetes/skills/` | `kubernetes-specialist` | `kubernetes-specialist` |
| `stacks/frontend/react/skills/` | `react-expert` | `react-expert` |
| `stacks/frontend/nextjs/skills/` | `nextjs-developer` | `nextjs-developer` |
| `stacks/frontend/angular/skills/` | `angular-architect` | `angular-architect` |
| `stacks/backend/fastapi/skills/` | `fastapi-expert` | `fastapi-expert` |

Each adapted skill should carry `ported-from:`, `ported-at:`, and
`adapted: true` in frontmatter when it borrows significant structure.
