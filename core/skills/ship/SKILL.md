---
name: ship
description: Commit and push current changes with a generated message, then open a PR. Every step confirms with the user. Never proceeds past a failing check.
source: core
triggers: /ship, commit and push, open a PR, ship this, create a pull request
---

# ship

A disciplined end-to-end shipping flow. Confirmation-gated; never pushes or
opens a PR without the user's explicit go-ahead.

## Preflight (no confirmation needed)

1. `git status` — list untracked, modified, staged files.
2. `git diff` and `git diff --cached` — inspect what's about to ship.
3. `git log -5 --oneline` — capture the project's commit message style.
4. `git branch --show-current` — confirm not on a protected branch.

If on `main`/`master`/`production`: stop, offer to create a feature branch named from the change.

## Step 1 — Stage

Show the user:

- Which files will be staged.
- Which files are being **excluded** (lock files, build output, secrets, large binaries).
- Any files with scan-secrets warnings (stop and surface these).

Stage with explicit paths, not `git add .`. Confirm before running.

## Step 2 — Message

Draft a commit message following the project's style (inferred from `git log`).

- Subject: imperative, ≤72 chars.
- Body: wrapped at 72, explains *why*, references issues if obvious from branch name or recent discussion.

Show the drafted message. Ask: "ship this message, edit, or abort?"

## Step 3 — Commit

Pass the message via heredoc to preserve formatting:

```
git commit -m "$(cat <<'EOF'
<subject>

<body>
EOF
)"
```

Never use `--no-verify` unless the user explicitly asks. If a pre-commit hook fails, stop and report — don't bypass.

## Step 4 — Push

Confirm the remote and branch before push.

- If branch has no upstream: `git push -u origin HEAD`.
- If branch has an upstream: `git push`.
- Never `--force`. If a non-fast-forward is rejected, stop and report.

## Step 5 — PR (optional)

If `gh` is available and the branch isn't `main`, offer to open a PR.

Draft title + body:

- Title: same as commit subject (or a summary if there are multiple commits).
- Body: what changed, why, how to test, any rollback note.

Use a heredoc. Do not include AI coauthor lines by default.

```
gh pr create --title "..." --body "$(cat <<'EOF'
## Summary
- <what changed>

## Why
<reason>

## Test plan
- [ ] <how to verify>
EOF
)"
```

Report the PR URL on success.

## Failure handling

- **Pre-commit hook fails:** stop, report the hook output, let the user decide.
- **Push rejected:** stop, show why (non-fast-forward, permission, protected branch). Never force.
- **PR creation fails:** commit and push are still done; report the error and let the user create the PR manually.

## Never

- Commit without showing the user the diff and the message.
- Push without showing the user the branch and remote.
- Force-push.
- Skip hooks.
- Commit files that triggered secret-scan warnings.
- Stage build artifacts, lockfiles (unless project convention requires), or anything gitignored.
