# Claude Code auto-mode setup (with dotclaude)

Auto-mode is Claude Code's built-in fast-classifier-based permission
system. It runs a small model on each tool invocation, buckets the
call into a risk tier, and only escalates the high-risk ones to a
user prompt.

Reference: <https://www.anthropic.com/engineering/claude-code-auto-mode>

This doc covers how to enable it, how it interacts with dotclaude's
static rules, and the failure modes to watch for.

## Mental model: classifier + static rules

```
                 ┌─────────────────────────────────┐
                 │      tool invocation            │
                 │  Bash("rm -rf .venv")           │
                 └────────────────┬────────────────┘
                                  │
                                  ▼
                 ┌─────────────────────────────────┐
   pre-deny      │   1. permissions.deny match?    │ ──yes──► HARD BLOCK (no classifier ever sees it)
                 └────────────────┬────────────────┘
                                  │ no
                                  ▼
                 ┌─────────────────────────────────┐
   pre-allow     │   2. permissions.allow match?   │ ──yes──► RUN (no classifier, no prompt)
                 └────────────────┬────────────────┘
                                  │ no
                                  ▼
                 ┌─────────────────────────────────┐
   classifier    │   3. auto-mode classifies risk  │
                 └────────────────┬────────────────┘
                                  │
                ┌─────────────────┼─────────────────┐
                ▼                 ▼                 ▼
            "low risk"        "medium"          "high risk"
                │                 │                 │
                ▼                 ▼                 ▼
              RUN              RUN OR PROMPT    PROMPT USER
                                (depending on
                                 your setting)
                                  │
                                  ▼
                 ┌─────────────────────────────────┐
   safety net    │   4. PreToolUse hook runs       │ ──block──► HARD BLOCK
                 │     (block-dangerous-commands)  │
                 └────────────────┬────────────────┘
                                  │ pass
                                  ▼
                                RUN
```

**The order matters.** Static deny is checked **first**, before the
classifier ever sees the command. Static allow is checked **second**.
Only commands that don't match either go to the classifier. The
runtime hook fires last — even on commands the classifier approved.

## Enabling auto-mode

In Claude Code's settings UI (or via `~/.claude/settings.json`),
look for the permission-mode field. Auto-mode names it explicitly;
older Claude Code versions called this "always allow safe commands"
or similar.

```jsonc
// ~/.claude/settings.json
{
  "permissionMode": "auto",  // or "ask" / "default" / etc.
  // dotclaude's permissions.allow/deny still apply on top of this
}
```

Restart Claude Code after the change. Verify with a known-safe command
like `git status` — it should run without a prompt.

## What auto-mode considers low-risk

Per Anthropic's design notes, the classifier treats these as low-risk
by default:

- Read-only filesystem ops (`ls`, `cat`, `find`, `grep`, `rg`).
- Read-only VCS (`git status`, `git diff`, `git log`).
- Information commands (`which`, `man`, `--help`).
- Common dev-server tools that exit on their own (`pytest`, `vitest`).
- Package-manager **inspection** subcommands (`pnpm list`, `pip show`).

It treats these as medium/high:

- Anything writing to the filesystem (`touch`, `mkdir`, `mv`, `cp`).
- Anything mutating VCS state (`git commit`, `git push`).
- Anything network-egress that isn't a recognized package manager.
- Anything matching the destruction taxonomy (covered by dotclaude's deny + hook).

## How dotclaude composes with auto-mode

The dotclaude defaults are **strictly additive** to auto-mode. They:

1. **Pre-allow** more than auto-mode classifies as low-risk by default.
   Auto-mode might prompt on `terraform plan` or `gh pr view`; dotclaude's
   stack overlays explicitly allow them, so the prompt never happens.
2. **Pre-deny** more than auto-mode catches.
   The classifier is general-purpose; dotclaude's deny list and hook
   know about specific patterns the classifier might miss (e.g., the
   `cat ~/.aws/credentials | curl …` exfiltration pattern).
3. **Hook safety net** fires regardless of how auto-mode classified
   the command. Even if the classifier let `git reset --hard` through
   somehow, the hook blocks it.

The result: the classifier handles the long tail; dotclaude handles
the specific patterns the classifier is likely to over- or under-rate.

## When you should NOT use auto-mode

Auto-mode reduces friction at the cost of running an extra model call
per tool invocation. Consider keeping default mode if:

- **Latency is critical** — the classifier adds a small but measurable
  per-call latency. On a tight loop, this stacks up.
- **You want explicit consent for everything** — high-stakes domains
  (production secrets management, financial data, medical records).
  Auto-mode is great for dev work, debatable for prod operations.
- **You're learning the agent's behavior** — early in adoption, the
  prompt friction is *the* feedback loop. Don't suppress it on day one.

## Verifying your setup

After enabling auto-mode + applying dotclaude defaults:

```bash
# 1. Should run without prompt (covered by dotclaude allow + classifier)
git status

# 2. Should run without prompt (covered by stacks/python allow)
pytest --collect-only

# 3. Should be HARD BLOCKED (covered by dotclaude deny + hook)
git push --force origin main

# 4. Should PROMPT (no specific rule, classifier rates as medium)
mv old-file.txt new-name.txt
```

If #3 only prompts (doesn't hard-block), your hook isn't installed —
re-run `/dotclaude-init`. If #1 prompts, your `permissions.allow` isn't
being read — check `.claude/settings.json` exists and is valid JSON.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Prompts on commands you've allowed | settings.json invalid JSON OR allow rule shape wrong (`Bash(cmd)` vs `Bash(cmd:*)`) | `python -m json.tool .claude/settings.json` to validate; check the matching pattern |
| Hook not firing | Hook file not executable OR not registered in `hooks.PreToolUse` | `chmod +x .claude/hooks/*.sh` and re-run `/dotclaude-init` |
| Hook errors with "jq: command not found" | Old version of the hook | dotclaude's current hook falls back to python and sed; update the hook file |
| Auto-mode running on every command despite explicit allow | Allow pattern doesn't match exactly. Auto-mode allow is matched by Claude Code's parser, which is strict | Check the exact arg shape — `Bash(npm:*)` matches `npm install` but not `npm  install` (double-space) |
| Surprising allow ("how did *that* run?") | A broad rule matched. Run `/dotclaude-permissions-audit` | Audit will name the rule; tighten or replace |

## Further reading

- Anthropic auto-mode design post: <https://www.anthropic.com/engineering/claude-code-auto-mode>
- Claude Code permissions docs: <https://docs.claude.com/en/docs/claude-code/iam>
- Claude Code hooks docs: <https://docs.claude.com/en/docs/claude-code/hooks>
- dotclaude threat model: `references/threat-model.md`
