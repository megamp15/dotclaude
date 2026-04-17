# Isolation techniques

Before the fix, isolate.

## `git bisect`

When the bug worked on an older commit:

```
git bisect start
git bisect bad              # current broken state
git bisect good <older-sha> # known-good commit
# repeat test, mark each bisect step bad/good until found
git bisect reset
```

Automate with `git bisect run <cmd>` if the check is a single exit code.

## Instrumentation over inspection

Don't re-read the same 200 lines for the third time. Add signal.

- Print / log at entry and exit of the suspect function with arg values.
- Log every branch taken in the suspect conditional.
- In async/concurrent code: log with timestamps and task/thread IDs.
- When logging, include enough context to distinguish one invocation from another (request ID, primary key).

Remove the instrumentation after the fix — or, better, convert the most useful of it into permanent structured logging at the right level.

## Minimal reproduction

Strip the bug from its surrounding context.

- Copy the failing case into a standalone script or test.
- Remove everything that isn't needed to reproduce.
- Each removal either preserves the bug (keep removed) or doesn't (restore).

The minimum reproduction is the best bug report and the best test.

## Delta debugging

When the bug reproduces but the input is huge (large JSON, long trace, complex state):

- Halve the input. Still reproduces? Halve again. Doesn't? Try the other half.
- Continue until you can't remove anything without losing the bug.

Tools like `picireny`, `creduce`, or custom scripts help for structured inputs.

## Wrong-question debugging

If you're stuck for more than 30 minutes, you're probably asking the wrong question. Restate:

- What do I know for sure is happening? (From logs, tests, repro.)
- What am I assuming but haven't verified?
- What would I see if my assumption is wrong?

Verify the assumption directly. Often the assumption is where the bug hides.

## When to use a debugger

- Program state is complex and hard to print.
- Need to inspect an object's full shape.
- Watching a value change across many frames.
- Post-mortem on a crash core dump.

When a debugger is available, it's almost always faster than `print`-based debugging for all but the simplest bugs. Don't avoid it out of habit.

## When to ask

- Bug touches a part of the system you don't own and can't access.
- Reproduction depends on data you don't have.
- Root cause is structural and the fix is a redesign.

Asking costs five minutes. Guessing costs hours.
