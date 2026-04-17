---
name: dotclaude-init
description: Initialize or update a project's .claude/ directory by merging dotclaude core + stack + project-specific config. Use when setting up a fresh repo, adopting dotclaude in an existing repo, or adding a new stack to an existing setup.
triggers: dotclaude-init, initialize dotclaude, setup claude code, bootstrap .claude, /dotclaude-init, adopt dotclaude
---

# dotclaude-init

Scan, interview, merge — in that order. The goal is to ask as few questions
as possible; anything that can be inferred from the repo should be inferred.

## When to use

- Fresh repo being set up with Claude Code for the first time.
- Existing repo being adopted into dotclaude.
- Re-init to add a newly-added stack (project grew a frontend, or picked up Python alongside Go).

Not for pulling upstream updates — that's `/dotclaude-sync`.

## Prerequisites

- `DOTCLAUDE_HOME` env var points at the local dotclaude repo (e.g. `~/code/dotclaude`).
- Skill runs from inside the target project's root directory.
- Git repo is clean (or changes are committed). Init writes many files — clean baseline makes review easy.

## Workflow

1. **Locate dotclaude** — resolve `DOTCLAUDE_HOME`; error clearly if unset.
2. **Scan the repo** → see `references/scanning.md`. Detect stack, frameworks, external services, existing `.claude/`.
3. **Present findings checklist** — show what was inferred; user confirms or corrects with AskUserQuestion.
4. **Ask the invisibles** → see `references/interview.md`. Only things grep can't reveal: rate limits, owners, reasons, sensitive paths.
5. **Merge** → see `references/merge.md`. Core + stack → flat `.claude/`; interview answers → `rules/project.md` + `CLAUDE.md` "Project context" section.
6. **Report** — list every file written, group by `source:` (core / stack / project), flag any guesses the user should review.

## Reference guide

| Topic | Reference | Load when |
|---|---|---|
| Stack & framework detection rules | `references/scanning.md` | Step 2 |
| Interview question bank | `references/interview.md` | Step 4 |
| Merge rules & source tagging | `references/merge.md` | Step 5 |

## Do not

- Do not interrogate the user about anything visible in code — detect it.
- Do not overwrite files lacking a `source:` frontmatter field. Those are project-owned forever.
- Do not run destructive operations (delete, reset) without explicit confirmation.
- Do not write secrets into any file. Answers go in text; credentials stay in env vars.
- Do not ask more than ~5 questions per run. More than that means the scan was too weak — fix the scan.
