---
name: commit
description: Write a well-formed commit message for the staged changes, following the repo's existing style. Never commits without confirmation.
source: core
triggers: /commit, write a commit message, commit message for this, commit these changes
---

# commit

Produce a commit message that matches the project's existing style and
actually explains *why* the change was made. Never commits without the
user's explicit go-ahead.

## Workflow

### 1. Inspect

- `git diff --cached` — what's staged.
- `git diff` — what's not staged (warn if the user seems to expect unstaged changes to be included).
- `git log -10 --pretty=format:'%s%n%b%n---'` — capture the style.
- `git log --pretty=%s | head -50` — get a feel for subject-line conventions.

### 2. Infer style

From recent commits:

- **Conventional Commits?** (`feat:`, `fix(scope):` prefix pattern)
- **Imperative vs past tense?** ("Add X" vs "Added X")
- **Subject length?** (some teams cap at 50, some at 72)
- **Body usage?** (most commits have bodies? one-liners? mixed?)
- **Issue references?** (`Fixes #123`, `Refs ABC-42`, none)
- **Scope component?** (`fix(auth): ...`) — does it use scopes consistently?

Match the project. Don't impose a style the project doesn't use.

### 3. Draft

Structure:

```
<subject — imperative, ≤ project's cap, no trailing period>

<body, wrapped at 72 chars, explains WHY>

<optional issue references>
```

Content rules:

- **Subject = the what** in imperative ("Add retry logic to NASA client").
- **Body = the why** ("NASA's NEO endpoint returns 502 overnight; retries recover without impacting p95").
- **Never list every file changed.** The diff shows that.
- **Don't narrate the session** ("After discussing with the user..."). The commit stands on its own.
- **No AI co-author lines** unless the user's repo conventions include them.

### 4. Show and confirm

Display the drafted message plus the list of files being committed. Ask:

- Ship this message?
- Edit the subject?
- Edit the body?
- Add/remove issue refs?
- Abort?

Do not proceed until the user chooses.

### 5. Commit (only on go-ahead)

Use a heredoc to preserve formatting:

```
git commit -m "$(cat <<'EOF'
<subject>

<body>

<refs>
EOF
)"
```

Never use `--no-verify`. If a pre-commit hook fails, report and stop — the user decides whether to fix or bypass.

### 6. Report

- Show the commit hash and one-line summary.
- Show `git status` after the commit.
- Do not push. Pushing is `ship`'s job.

## Good vs bad

### Bad

```
Update files

fixed stuff
```

### Bad (narrates the session)

```
I refactored the auth module

After the user asked me to clean up the auth code, I extracted
the token parsing into a helper and added a type hint.
```

### Bad (describes the diff, not the why)

```
Change line 42 in auth.py

Changed the return value from None to an empty dict in
parse_token().
```

### Good

```
Fix: token parser returns {} instead of None on empty input

Callers iterate over the result without a None check, so an empty
token was raising AttributeError deep in request handling. Returning
{} matches the documented contract and removes the crash.

Fixes #421.
```

## Special cases

- **WIP commits** — allowed but labeled `WIP: <what>`. Remind the user these usually get squashed before merge.
- **Revert** — subject is `Revert "<original subject>"`, body explains *why* reverting, references the original SHA.
- **Merge commits** — don't write these with this skill; let `git merge` handle it.
- **Squashing before push** — offer this if the branch has several small WIP commits that would look noisy in the main branch's log.
