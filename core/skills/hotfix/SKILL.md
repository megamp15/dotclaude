---
name: hotfix
description: Make the smallest change that stops a production incident, ship it, clean up afterward
source: core
---

# Hotfix

Use when: something is broken in production right now, blast radius is
live, every minute of debate is a minute of user pain.

Not for: refactors, "while we're in here" improvements, post-mortem items.
Hotfix is deliberately narrow.

## Mindset

- **The goal is to stop the bleeding.** Not elegant code. Not the "right" fix. The *smallest* change that restores service.
- **Rollback first, fix second — if rollback is safe.** A clean rollback to a known-good version beats a rushed forward-fix almost every time.
- **Paranoid humility.** Under time pressure, confirmation bias is worst. Check every assumption.

## Workflow

### 1. Confirm the scope

Before touching anything:

- **What is actually broken?** Error rate, what endpoint, what user segment, since when.
- **What deploy/change correlates with the break?** Almost always there is one. If you can't find it, you're about to hotfix the wrong thing.
- **Is it worse than doing nothing?** Sometimes the safe option is: freeze writes, degrade a feature, post a status page. Hotfix ≠ the only response.

### 2. Decide: roll back or roll forward

**Roll back when:**
- The regression is clearly from the latest deploy.
- The previous version is known good and still compatible (DB schema, external contracts).
- Rollback is fast and well-understood in this project.

**Roll forward when:**
- Rolling back re-introduces a worse bug or a known data corruption.
- Schema changes or irreversible migrations have landed since the last good version.
- The bug is from a config/data change, not code.

If in doubt, propose rollback to the user. Don't "improve things" on a live incident.

### 3. Minimal fix only

If rolling forward:

- One commit. One file if possible. One function if possible.
- **No** drive-by formatting, no refactors, no renames, no adjacent "while I'm here" fixes.
- The diff should be reviewable by a tired on-call in 30 seconds. Their bar is "does this make it worse?"
- **A one-line guard is often the right fix.** Correct the bleed now; do the proper fix in a follow-up PR.

### 4. Test the fix before shipping

Even under pressure:

- Reproduce the bug in a scratch test or local repro (same conditions if possible — same payload, same state).
- Apply the fix. Re-run the repro. It's gone.
- Run the immediately-related tests. If they were green before, they must be green now.

If you cannot reproduce the bug, **stop**. Shipping an untested hotfix to a bug you can't reproduce is flipping coins with prod.

### 5. Ship

- Commit message: `hotfix: <one-line what + why>`. Reference the incident or alert.
- Tag/label the PR as hotfix so it gets expedited review + CI.
- Announce in the incident channel: what you're shipping, when, rollback plan.
- Watch metrics after deploy. Don't declare victory; wait for signal.

### 6. Close the loop

After the dust settles (same day, not "some day"):

- **Proper fix PR** if the hotfix was a band-aid. Link to the incident and the hotfix commit.
- **Regression test** that would have caught this. This is non-negotiable. "A bug gets fixed only once in a well-maintained codebase" — write the test.
- **Post-mortem input:** what got through, what alerts helped/hurt, what would have shortened MTTR.

The difference between a team that hotfixes rarely and one that hotfixes constantly is almost entirely whether step 6 happens.

## Required confirmations

This skill must confirm with the user before:

1. **Rollback** (specify target version or commit).
2. **Deploying the forward-fix**.
3. **Skipping the regression test** — only with an explicit follow-up task created.

## Anti-patterns

- "While we're in here, let me also fix…" — that's the #1 way hotfixes cause incidents.
- Hotfixing off main with untested local changes.
- Logging-only changes shipped as "hotfix." If it doesn't change behavior, it's diagnostic instrumentation; label it as such.
- Reverting a migration inside a hotfix. Data changes have their own process.
- Declaring the incident over when the fix deploys but before metrics recover.

## When to escalate instead of hotfixing

- You need production credentials you don't have.
- The fix requires touching someone else's service / team's code.
- The bug is in a third-party service / dependency.
- Data is being corrupted *right now* and a code fix doesn't stop it — you need to pause the writer first.

In all of these, the fastest path to "stopped bleeding" is a human, not a commit.
