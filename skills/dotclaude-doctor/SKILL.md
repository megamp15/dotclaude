---
name: dotclaude-doctor
description: Diagnose a dotclaude install or repo checkout. Checks DOTCLAUDE_HOME, framework links, skill discoverability, flat stack-skill drift, JSON parseability, settings hooks, source tags, optional MCP config files, and common broken-install symptoms.
triggers: dotclaude-doctor, /dotclaude-doctor, diagnose dotclaude, check dotclaude install, skills not loading, hooks not firing, broken .claude
---

# dotclaude-doctor

Run a fast health check before debugging by hand.

## Workflow

1. Locate dotclaude:
   - Prefer `DOTCLAUDE_HOME`.
   - Fall back to the current repo if it has `core/`, `skills/`, and `stacks/`.
2. Run `scripts/dotclaude-doctor.sh` from the dotclaude repo if available.
3. If the script is unavailable, perform the manual checklist below.
4. Report failures first, then warnings, then what looks healthy.

## Manual checklist

- `DOTCLAUDE_HOME` points at the dotclaude repo.
- `~/.claude/skills/dotclaude-init/SKILL.md` exists or framework skills are
  otherwise linked/copied into the agent's skill directory.
- Core settings parse as JSON.
- `core/skills/*/SKILL.md`, `skills/*/SKILL.md`, stack skills, and MCP skills
  have `name` and `description` frontmatter.
- Source-managed skills under `core/` and `stacks/` have `source:`.
- No `stacks/*/skills/*.md` flat skill files remain.
- Hook paths registered in `core/settings.partial.json` exist in `core/hooks/`.
- Optional MCP JSON files parse.

## Output

```text
dotclaude doctor
Status: pass | warn | fail

Failures:
- ...

Warnings:
- ...

Healthy:
- ...

Next steps:
- ...
```

