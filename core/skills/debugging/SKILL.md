---
name: debugging
description: Debugging hub with tactical and advanced modes. Tactical mode reproduces, isolates root cause, applies the smallest fix, and adds a regression test. Advanced mode escalates for heisenbugs, leaks, deadlocks, races, profilers, traces, core dumps, eBPF, and production-only failures.
source: core
triggers: /debug, /debug-fix, /debug-wizard, debug this, find the bug, fix this error, reproduce issue, regression, heisenbug, production debugging, memory leak, deadlock, race condition, flame graph, perf, eBPF, bcc, bpftrace, strace, ltrace, lsof, gdb, lldb, core dump, pprof, heap dump, jstack, py-spy, distributed trace, correlation ID
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/debugging-wizard
ported-at: 2026-04-17
adapted: true
---

# debugging

One debugging skill with an escalation path.

## Mode selection

| Signal | Mode |
|---|---|
| Error message, failing test, issue, reproducible bug, "fix this" | `tactical` |
| Intermittent, production-only, performance, leak, deadlock, race, crash dump | `advanced` |

Start tactical unless the bug already shows advanced signals. Escalate when
basic reproduction and instrumentation stop producing evidence.

## Mode: tactical

Use the disciplined fix loop:

1. State expected, actual, and trigger conditions.
2. Reproduce the bug. Prefer a failing test.
3. Isolate the root cause. Work backward from the symptom; instrument instead
   of staring at code indefinitely.
4. State the root cause in one sentence before editing.
5. Make the smallest fix that addresses the cause.
6. Add or promote the regression test.
7. Run the focused test and relevant suite.
8. Report what broke, why, what changed, and residual risk.

Tactical-mode references (load on demand):

- [`references/tactical-bug-archetypes.md`](references/tactical-bug-archetypes.md)
- [`references/tactical-isolation.md`](references/tactical-isolation.md)

## Mode: advanced

Use this for hard bugs: memory leaks, deadlocks, race conditions, heisenbugs,
distributed failures, production crashes, and misleading performance symptoms.

Escalation ladder:

1. Cheapest signal first: logs, metrics, focused traces.
2. Language-level profiler or debugger.
3. Process inspection: thread dump, heap dump, core dump, pprof, py-spy,
   async-profiler, dotnet-dump.
4. System tracing: strace, ltrace, perf, ftrace, eBPF/bpftrace.
5. Distributed tracing by correlation ID.

Advanced-mode references (load on demand):

- [`references/advanced-process-state.md`](references/advanced-process-state.md)
- [`references/advanced-system-tracing.md`](references/advanced-system-tracing.md)

## Output format

```text
Symptom:
Expected:
Actual:
Reproduction:
Root cause:
Fix:
Verification:
Follow-ups:
```

For performance work:

```text
Metric:
Baseline:
Profile:
Hotspot:
Change:
After:
Gain:
```

