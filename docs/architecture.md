# Architecture

dotclaude is a layered source repo that renders into flat target-agent
layouts.

## Source Layers

```text
core/        universal rules, skills, agents, hooks, MCP defaults
stacks/      language/framework/infra overlays
skills/      dotclaude framework workflows and renderers
commands/    slash-command wrappers
scripts/     backing scripts and validators
```

`core/` and `stacks/` are sources. They are not copied wholesale. Init and
renderer skills merge only the pieces a target repo needs.

## Target Shape

After `/dotclaude-init`, a project looks like this:

```text
my-project/
├── .claude/
│   ├── CLAUDE.md
│   ├── settings.json
│   ├── agents/
│   ├── hooks/
│   ├── rules/
│   │   ├── python-style.md   # source: stacks/python
│   │   └── project.md        # project-owned
│   └── skills/
└── .mcp.json
```

Files with `source:` are upstream-owned. Files without it are project-owned and
must not be overwritten by sync.

## Merge Model

```text
dotclaude source                target repo
---------------                 -----------
core/CLAUDE.base.md       -->   .claude/CLAUDE.md
core/settings.partial     -->   .claude/settings.json
core/rules,skills,hooks   -->   .claude/rules,skills,hooks
stacks/<name>/*           -->   layered onto the same flat target
interview answers         -->   project-owned sections/files
```

JSON settings are deep-merged. Stack settings overlay core settings. Project
local settings stay separate in `.claude/settings.local.json`.

## Stack Layering

Stacks are additive, not exclusive. A Python API running in Docker, deployed to
Kubernetes, managed by Terraform, and tested in GitHub Actions should use all
matching stacks:

```text
python + docker + kubernetes + terraform + github-actions
```

Infra stacks should not conflict with language stacks. When they do, the stack
with the more specific operational boundary should own the rule.

## Skills vs Commands

Most workflows are skills because they should activate from natural language.
Commands exist for named framework operations where deterministic menu
invocation matters, such as `/dotclaude-init` and `/dotclaude-sync`.

## Multi-Agent Portability

Good source content is portable. Loader mechanics are not. The renderers adapt
the same canonical content into:

- Claude Code `.claude/`
- Cursor `.cursor/rules/*.mdc`
- GitHub Copilot custom instructions
- OpenCode config and commands
- Plain `AGENTS.md`

Each renderer is explicit about lossy features. Hooks and fine-grained command
permissions do not translate equally across agents.

