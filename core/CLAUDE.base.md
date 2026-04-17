<!-- source: core -->
# CLAUDE.md

Universal instructions that apply in every project. Stack- and
project-specific sections are appended below this by `dotclaude-init`.

## Working principles

- **Scope discipline.** Do what was asked, nothing more. If you spot a
  related issue, mention it — don't silently fix it in the same change.
- **Prefer editing over creating.** Don't make a new file when an
  existing one is the right home for the change.
- **Read before writing.** Always inspect the current file before you
  edit it. Don't guess at contents.
- **Small, verifiable steps.** Prefer 5 small changes you can verify
  over one large change you can't.
- **Match existing style.** Follow the patterns already in the codebase
  — naming, structure, error handling, test shape — even if you'd have
  chosen differently on a blank slate.

## Communication

- Lead with what changed and why. Skip preamble like "I'll now...".
- Surface risks, assumptions, and alternatives you considered and rejected.
- When you don't know, say so. Don't pattern-match into a confident guess.
- Ask one question at a time when clarification is needed. Never
  interrogate the user with a wall of questions.

## Code comments

- Explain *why*, not *what*. The code already shows what.
- No narration comments (`// increment counter`, `# return result`).
- Document non-obvious trade-offs, constraints, and gotchas.
- Leave `TODO(owner): ...` comments only when genuinely incomplete —
  with a handle so the owner is clear.

## Editing and refactoring

- **Never mix behavior changes with refactors** in the same commit.
  Refactor first (tests still pass), commit, then change behavior.
- Never commit commented-out code. Delete it; git remembers.
- Never introduce dead code, unreachable branches, or unused imports.
- If a refactor grows unexpectedly, stop and report — don't sprawl.

## Testing

- New behavior needs a test that fails before the change and passes after.
- Never delete a failing test to "fix" a failure unless the test itself
  is demonstrably wrong. Explain why if you do.
- Running tests before declaring something done is not optional.

## Git & shipping

- Never commit unless asked explicitly.
- Never push unless asked explicitly.
- Never force-push to a shared branch.
- Never run destructive git commands (`reset --hard`, `clean -fdx`,
  `branch -D`) without confirmation.
- Commit messages describe *why* in the body; the subject line is the
  *what* in imperative mood.

## Guardrails

- Never write secrets (API keys, tokens, passwords) into any file.
  If the user pastes one, warn and redact.
- Never edit files matching `.env*`, `*.pem`, `*.key`, `*/secrets/*`,
  `*/credentials/*` without explicit confirmation.
- Never run commands that could be destructive on production data
  (direct DB writes, `DROP`, `DELETE ... WHERE 1=1`, `rm -rf /`).
- For any hard-to-reverse operation, confirm first.
