# Audit workflow

How to read `/dotclaude-permissions-audit` output and act on it.

The audit is **read-only**. It compares your project's
`.claude/settings.json` against the dotclaude defaults that *would*
ship today and prints a structured report. It does not modify anything.

## Running the audit

```
/dotclaude-permissions-audit
```

Or directly:

```
bash .claude/scripts/dotclaude-permissions-audit.sh
```

Optional flags:

```
--diff           # show full deep-diff against current dotclaude defaults
--unused         # additionally try to detect allow rules with no recorded use
--strict         # treat any over-broad allow as a finding (else only warns)
```

## Anatomy of the output

The report has six sections. They're ordered worst-first:

```
=== dotclaude permissions audit ===

[CRITICAL]   Over-broad allow rules                ← act on these first
[CRITICAL]   Missing deny rules from threat model
[WARNING]    Hook is registered but not executable
[INFO]       Allow rules covered by stack overlay   ← prune candidates
[INFO]       Drift from current core/stack defaults
[OK]         Coverage matches recommended defaults

=== summary: 2 critical, 1 warning, 4 info ===
```

## How to act on each section

### CRITICAL — Over-broad allow rules

A rule like `Bash(*)` or `Bash(rm:*)` defeats the model. The audit
flags any pattern that:

- Matches `*` in the command-name slot.
- Allows a command in the deny taxonomy (e.g., `Bash(curl:*)` overlaps
  with the `curl|sh` deny).
- Allows entire interpreter invocations without subcommand scoping
  (`Bash(python:*)` is borderline — flagged in `--strict` mode).

**Action:** Either narrow the allow (specify the subcommand) or remove
it entirely. The audit suggests a narrowed version when possible.

### CRITICAL — Missing deny rules from threat model

The audit cross-references your `permissions.deny` against the
eight-category threat model in `references/threat-model.md`. If you
have a custom settings.json that drifted from the dotclaude defaults
and is missing, e.g., the `git --no-verify` deny, it gets flagged.

**Action:** Run `/dotclaude-init` to re-merge core defaults, OR copy
the missing rule from `core/settings.partial.json` into your project
settings.

### WARNING — Hook registered but not executable

A `hooks.PreToolUse` entry references `block-dangerous-commands.sh`
but the file isn't executable (`chmod +x` missing) or doesn't exist.
This is the safety-net layer; if it doesn't run, the threat model is
half-defended.

**Action:** `chmod +x .claude/hooks/*.sh`. If the file is missing
entirely, re-run `/dotclaude-init`.

### INFO — Allow rules covered by stack overlay

If you've manually added `Bash(pytest:*)` and the python stack overlay
already provides it, the audit suggests pruning the duplicate. Keeps
your project settings.json focused on actual project-specific rules.

**Action:** Remove from project settings; rely on the stack overlay
(which dotclaude-init merges in).

### INFO — Drift from current core/stack defaults

Compares your active settings against what dotclaude would generate
today from `core/` + applicable `stacks/`. Drift might mean:
- dotclaude added new safe-allow rules since you last init'd → consider re-init.
- You consciously diverged → fine, just confirm.

**Action:** `--diff` to see the full delta. If any look useful, run
`/dotclaude-sync` to pull the latest deltas selectively.

### OK — Coverage matches recommended defaults

Self-explanatory. The audit confirms the headline categories are
covered.

## Common findings in practice

After running on a fresh project that's just had `/dotclaude-init`:

- Almost always **all OK** — the defaults are aligned by construction.
- Drift shows up over weeks as dotclaude evolves; expect 2–5 INFO
  items per quarter.

After running on a project with hand-edited settings (typical):

- 1–3 CRITICAL findings (usually a too-broad rule someone added in a
  hurry).
- 0–1 WARNING (chmod issues are common after `git clone`).
- 4–10 INFO findings (drift accumulates).

After running on a project that *never* used dotclaude-init:

- 5+ CRITICAL findings (no deny rules at all, or `Bash(*)` everywhere).
- The right move is `/dotclaude-init`, not piecemeal fixes.

## What the audit does NOT check

- Your `.claude/settings.local.json` (gitignored, per-developer).
  Local overrides are intentionally invisible to the audit.
- The actual classifier behavior of Claude Code's auto-mode. The audit
  is static; runtime classifier decisions are out of scope.
- MCP-specific permission rules — those belong to each MCP's own config.
- Whether your team *should* allow a rule. The audit reports facts;
  you decide.

## When to run

- After `git clone` or `git pull` that changes `.claude/settings.json`.
- After any manual edit to `.claude/settings.json`.
- Before enabling auto-mode for the first time (sanity check).
- Every few weeks as a hygiene pass.

The audit is fast (sub-second on a normal settings file). No reason
to skip it.
