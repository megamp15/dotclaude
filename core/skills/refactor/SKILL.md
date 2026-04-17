---
name: refactor
description: Refactor code safely — tests as a safety net, small steps, no behavior change. Never mixes refactor with feature work.
source: core
triggers: /refactor, refactor this, clean up, extract function, simplify, restructure
---

# refactor

Refactor = change structure without changing behavior. If behavior
changes, it's not a refactor.

## Preconditions

A refactor is safe to start only when:

1. **Tests exist** for the code being refactored. If they don't, pause and
   write characterization tests first — tests that capture the *current*
   behavior (warts and all) so you can tell when you've broken it.
2. **The suite is green** before you start. Never refactor on a red bar.
3. **The scope is one thing.** Rename X, extract Y, or inline Z — not all three at once.

If any precondition isn't met, stop. Fix the precondition first, as its
own commit.

## Workflow

### 1. Name the smell

State, in one sentence, what's wrong:

- "This function is 200 lines and does three unrelated things."
- "These two classes reach into each other's fields."
- "This conditional chain keeps growing with each new case."

If you can't name the smell precisely, you don't have a refactor target — you have "I don't like the look of this code".

### 2. Pick the smallest transformation

| Smell | First transformation |
|---|---|
| Long function | Extract function for a cohesive block |
| Duplicated code (third occurrence) | Extract function or method |
| Data clump (same 3 params always together) | Introduce parameter object |
| Feature envy (method uses another class's data more than its own) | Move method |
| Switch on type | Replace conditional with polymorphism (only if truly polymorphic) |
| Large class | Extract class |
| Primitive obsession | Replace primitive with value object |
| God object | Extract class per responsibility |
| Magic numbers | Replace with named constant |
| Nested conditionals | Guard clauses, early return |

Pick the *smallest* step. Big refactors are sequences of small refactors, not one heroic change.

### 3. Apply

- Make the change.
- Run the tests.
- Commit.

Yes — commit after each step. The git log is the safety net.

### 4. Repeat

Go back to step 1 if there's more. Stop when the smell is gone or you've hit a natural boundary.

## Rules

- **No behavior changes.** If you spot a bug mid-refactor, note it, finish the refactor, then fix the bug in a separate commit.
- **No new features.** Same rule.
- **No style-only changes mixed in.** Rename-and-refactor is two commits.
- **Tests stay green at every step.** If a step breaks tests, undo it, split smaller.
- **Use the tools.** Rename-via-IDE is safer than find-replace. Extract-function refactorings in many IDEs update callers automatically.

## When to stop

- Diminishing returns. The next step makes the code 2% better and risks 5% complexity.
- You're about to change the external interface. That's a bigger conversation.
- You find a bug, a missing test, or a design question. Back out, handle it, come back.

## When NOT to refactor

- Right before a release. Save it for after.
- Code that's about to be deleted or replaced.
- Code you don't understand. Understand first; refactoring to understand is expensive debugging.
- Test code, unless the tests are actively blocking real work (hard to read, slow, flaky).

## The "Make the change easy" move (Kent Beck)

When a refactor is preparing for a specific feature:

1. Refactor so that the upcoming feature is an easy change. Commit.
2. Make the easy change (feature). Commit.

Keep those commits separate. Future you (and reviewers) will thank you.
