---
description: Audit .claude/settings.json for over-broad allow rules, missing deny coverage from the threat model, hook misconfigurations, and drift from current dotclaude defaults. Read-only — does not modify anything. Pairs with the permissions-tuner skill.
---

Run a read-only audit of the project's permissions config.

## What it does

1. Loads `.claude/settings.json`.
2. Cross-references `permissions.allow` against the over-broad-allow
   patterns (nuclear: `Bash(*)`; borderline: `Bash(rm:*)`, `Bash(curl:*)`).
3. Cross-references `permissions.deny` against dotclaude's eight-category
   threat model — flags any category with no matching deny rule.
4. Verifies every hook registered in `hooks.PreToolUse` actually exists
   on disk and is executable.
5. (When `DOTCLAUDE_HOME` is set) compares against the current
   `core/settings.partial.json` and reports drift.
6. Prints a structured findings report and exits non-zero if any
   CRITICAL findings are present.

It does NOT modify `settings.json`. It does NOT change permissions.
It only reports.

## How to invoke

- **`/dotclaude-permissions-audit`** — default report.
- **`/dotclaude-permissions-audit --diff`** — also show the full
  drift detail vs current `core/settings.partial.json`.
- **`/dotclaude-permissions-audit --strict`** — treat broad
  interpreter allows (`Bash(rm:*)`, `Bash(curl:*)`, `Bash(bash:*)`, etc.)
  as critical findings instead of warnings.
- **`/dotclaude-permissions-audit --json`** — emit machine-readable
  JSON instead of the formatted report (useful in CI).

The slash command delegates to:

```
bash .claude/scripts/dotclaude-permissions-audit.sh "$@"
```

## After the audit

Read the report top-to-bottom (worst-first ordering: CRITICAL →
WARNING → INFO → OK). For each finding:

- **CRITICAL** — act now. The rules describe how to fix in one line.
- **WARNING** — usually a `chmod` or a path issue; quick fix.
- **INFO** — drift; consider `/dotclaude-sync` or accept and move on.

If the report shows multiple CRITICAL findings, the right move is
almost always to re-run `/dotclaude-init` rather than fix piecemeal
— init does the right deep-merge atomically.

For deeper guidance on what each finding means and the philosophy
behind the recommendations, read `.claude/skills/permissions-tuner/SKILL.md`
and its three references (`auto-mode-setup.md`, `threat-model.md`,
`audit-workflow.md`).

## Anti-patterns

- **Don't dump the full report at the user.** Synthesize: lead with
  the count and worst category, then enumerate critical findings, then
  ask whether to proceed. The full report is for the audit script's
  own output; your synthesis is the conversation.
- **Don't fix findings without confirming.** The audit suggests fixes;
  the user decides which to apply. Many "drift" findings are
  intentional divergences.
- **Don't run the audit from inside the agent's response loop on every
  turn.** It's a hygiene check, not a per-turn assertion. Once a week
  or after manual settings.json edits is the right cadence.

$ARGUMENTS
