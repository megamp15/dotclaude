# Permissions

dotclaude follows an auto-mode-aligned permission model: broad allow rules for
safe/read-only work, targeted deny rules for dangerous behavior, and runtime
hooks for patterns static matching cannot catch.

## Layers

| Layer | Lives in | Purpose |
|---|---|---|
| Allow rules | `settings.partial.json` | Safe-by-intent commands run without prompts. |
| Deny rules | `settings.partial.json` | Destroy, exfiltrate, bypass review, or weaken security. |
| Safety hooks | `core/hooks/` | Catch wrapped or escaped dangerous patterns. |
| User overrides | `.claude/settings.local.json` | Local habits without polluting the repo. |

The full tuning guide lives in
[../core/skills/permissions-tuner/SKILL.md](../core/skills/permissions-tuner/SKILL.md).

## Audit

Run:

```text
> /dotclaude-permissions-audit
```

Useful variants:

```bash
/dotclaude-permissions-audit --diff
/dotclaude-permissions-audit --strict
/dotclaude-permissions-audit --json
```

The audit is read-only. It flags over-broad allow rules, missing deny coverage,
hook misconfigurations, and drift from current dotclaude defaults.

