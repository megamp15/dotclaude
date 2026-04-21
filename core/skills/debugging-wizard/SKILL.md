---
name: debugging-wizard
description: Advanced debugging — hard bugs that span processes, nodes, or languages. Core dumps, eBPF tracing, flame graphs, memory leaks, deadlocks, race conditions, distributed traces, production heap dumps, and the discipline of bisection. Complements `core/skills/debug-fix` (tactical) and `core/skills/sre-engineer` (incident process).
source: core
triggers: /debug-wizard, heisenbug, production debugging, memory leak, deadlock, race condition, flame graph, perf, eBPF, bcc, bpftrace, strace, ltrace, lsof, gdb, lldb, core dump, pprof, async-profiler, heap dump, jstack, py-spy, scalene, distributed trace, correlation ID
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/debugging-wizard
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# debugging-wizard

Advanced debugging — when the bug resists logs and breakpoints.
Activates on hard bugs: memory leaks, deadlocks, heisenbugs,
distributed-system mysteries, low-level perf issues.

> **See also:**
>
> - `core/skills/debug-fix/` — tactical "find a bug, fix it"
> - `core/skills/sre-engineer/` — incident response wrapper
> - `core/skills/monitoring-expert/` — observability prerequisites
> - `core/skills/test-master/references/flaky-and-fast.md` — flaky
>   tests often = concurrency bugs
> - `stacks/python/skills/python-pro/references/performance.md` —
>   Python-specific profiling

## When to use this skill

- Bug reproduces intermittently, resists breakpoints.
- Memory grows without bound in production.
- Process deadlocks or hangs under load.
- Data race / concurrency issue.
- Slow code where the hotspot isn't where you'd expect.
- Distributed bug: spans multiple services.
- Production crash with only a core dump or a trace.
- "Works on my machine", fails in prod.

## References (load on demand)

- [`references/process-state.md`](references/process-state.md) —
  attaching to running processes (gdb, lldb, py-spy, jstack,
  dotnet-dump), inspecting threads, heap dumps, core dumps, live
  stack traces.
- [`references/system-tracing.md`](references/system-tracing.md) —
  syscalls and kernel-level observability: strace, ltrace, perf,
  ftrace, eBPF / bcc / bpftrace, flame graphs, I/O and network
  tracing, distributed tracing for the same kinds of questions
  across services.

## Core workflow

1. **State the bug crisply.** Precise reproducer > vague
   description. "10% of users see 503 on checkout after 3+ items
   in cart" beats "something is broken".
2. **Bisect on time and code.** When did it start? What changed?
   `git bisect` for code; timestamps for infra.
3. **Make it reproducible first.** If it's intermittent,
   instrument until it's deterministic or the trigger is known.
4. **Start with the cheapest tool.** Log line > metric > trace >
   profiler > debugger > eBPF. Escalate deliberately.
5. **Change one variable at a time.** Multi-change commits make
   bisection useless.
6. **Write down hypotheses.** Bug hunts produce tribal knowledge
   that evaporates; record each assumption and what disproved it.
7. **Fix the cause, not a symptom.** A retry loop that hides a
   deadlock isn't a fix.

## Defaults

| Situation | First tool |
|---|---|
| Slow function | Language profiler (py-spy, async-profiler, pprof) |
| Memory leak | Heap dump diff; memray/jmap/pprof |
| Hung process | Thread dump / stack sampling |
| Crashed process | Core dump + debugger |
| Hot syscall / I/O | strace / bpftrace |
| Mystery network behavior | tcpdump / Wireshark + eBPF |
| Distributed weirdness | Trace a single request end-to-end |
| Race condition | TSAN / Helgrind / Go `-race` / logged timestamps |
| Deadlock | Thread dump analysis |
| Production-only bug | Prod-safe profiler (py-spy, async-profiler attach) |
| "Sometimes slow" | Continuous profiling (Parca, Pyroscope, gProfiler) |
| Test flake | `pytest --repeat-each 100 --randomly-seed=N` |

## Anti-patterns

- **Adding prints and praying.** Fine for 30s; don't let it be
  your whole strategy.
- **Guessing without evidence.** Each hypothesis needs a test
  that can disprove it.
- **Optimizing without profiling.** Your intuition about
  hotspots is usually wrong.
- **Fixing symptoms.** "It's fine if we retry" hides bugs.
- **Breaking the repro.** Adding a print may alter timing and
  mask a race. Use tools that observe without perturbing.
- **Not writing it down.** You'll forget, and the next time will
  be just as long.
- **Blaming the tool.** OS, kernel, compiler, standard library
  are almost never the bug. It's the code you wrote yesterday.
- **Leaving instrumentation behind.** Ad-hoc prints in prod =
  noise; remove after the hunt.

## Output format

For a production bug investigation:

```
Symptom:       <user-visible>
Blast radius:  <who is affected>
Started:       <timestamp; what changed>
Environment:   <where reproduces>

Hypothesis log:
  H1:  <guess> — <test> — <disproved / confirmed>
  H2:  ...
  H3:  ...

Root cause:    <what actually happened>
Fix:           <smallest change>
Verification:  <how you confirmed the fix>
Follow-ups:
  - <test / guard / metric to prevent recurrence>
  - <doc / runbook>
```

For a performance debug:

```
Metric:        <wall time / latency p99 / throughput>
Baseline:      <measurement>
Profile:       <tool + flame graph link>
Hotspot:       <function / call / syscall>
Why hot:       <N calls × M us each = X total>
Change:        <what was done>
After:         <measurement>
Gain:          <% improvement>
```

## The "can you reproduce it" rubric

How easy is it?

- **Always** — run in a debugger. Done.
- **Often (1 in N)** — loop the test N×; attach profiler; add
  randomized seeds; log inputs.
- **Rarely** — instrument prod (trace IDs, extra metrics); wait
  for the next occurrence; capture heap/core dump for post-
  mortem.
- **Only in prod** — mirror traffic to staging; use prod-safe
  observability (py-spy, eBPF); avoid breakpoints.

Before fixing, get out of "rarely" as much as possible.

## Bisection

### `git bisect`

```bash
git bisect start
git bisect bad HEAD
git bisect good v1.9.0
# git checks out middle commit; you test
# if bug: git bisect bad; if not: git bisect good
# repeats until narrowed
git bisect reset
```

Automate the test:

```bash
git bisect run ./scripts/repro-test.sh
```

`repro-test.sh` exits 0 (good) or non-zero (bad).

Caveats:

- Flaky tests break bisection — stabilize first.
- Bug might depend on state; ensure each checkout is clean.

### Time-based bisection

When bug started at a specific time but no code change:

- Dependency updated? `pip freeze` vs. last week.
- Infra change? K8s / Terraform apply logs.
- Data change? Schema migration.
- Traffic change? Load went up.
- Upstream provider change? Their status page.

## Reading a flame graph

Flame graph = call stacks stacked visually; width = time spent.

- **Tallest stacks** — deepest call chains.
- **Widest frames** — where time is spent.
- **Plateaus** (wide single block at top) — the actual hotspot.
- **Many similar stacks** — symptom of recursion / tight loops.
- **Holes at top** — missing symbols; improve debug info.

Tools: `speedscope` (web), `flamegraph.pl` (Brendan Gregg),
[profiler.firefox.com](https://profiler.firefox.com).

## Thread dump / stack trace analysis

Jargon by language:

- **Java** — `jstack <pid>` or `kill -3 <pid>`.
- **Go** — `SIGQUIT` or HTTP `pprof`'s `/debug/pprof/goroutine?debug=2`.
- **Python** — `py-spy dump --pid <pid>`.
- **Node.js** — `inspect=9229`, connect DevTools; `async_hooks`
  for tasks.
- **.NET** — `dotnet-dump` + `dotnet-stack`.

### Reading

- **All threads stuck on same lock** → deadlock.
- **Threads stuck in `park`/`Condition.wait`** with no progress
  → deadlock likely; find holder.
- **Many threads in DB wait** → connection pool saturation or
  slow query.
- **Growing number of threads** → thread pool misconfigured or
  leak.
- **One thread pegged at 100% CPU** → infinite loop; check the
  code at the top of that stack.

## Memory leak investigation

1. **Confirm it's a leak**, not high steady-state usage:
   - Graph RSS over time. Does it grow unbounded? Or plateau?
   - Run load, stop load, wait 5 min. Does RSS drop? If not,
     leak.
2. **Identify the retainer**:
   - Java: `jmap -histo <pid>`; heap dump to MAT / VisualVM.
   - Python: `tracemalloc`; `memray` for serious cases; `objgraph`
     for reference graphs.
   - Go: `pprof heap -diff_base` between snapshots.
   - Node.js: `--inspect` + DevTools Memory; `heapdump` + Chrome.
3. **Find the leak source**:
   - What objects have unexpectedly high counts?
   - Who holds a reference to them? (retaining path)
   - Is there a cache / global with unbounded growth?
   - Event-listener leak? Every `addEventListener` has a
     corresponding `remove`?

## Deadlock / race condition

### Deadlock

- **Symptoms**: threads stuck, CPU 0%, work doesn't progress.
- **Diagnosis**: thread dump; look for reciprocal lock waits.
- **Prevention**: consistent lock ordering, lock-free
  alternatives, timeouts on locks.

### Race condition

- **Symptoms**: "sometimes wrong"; reproduces under load; fine
  single-threaded.
- **Diagnosis**: TSAN (C/C++), Go `-race`, Helgrind; logging with
  thread IDs; careful code review of shared state.
- **Prevention**: immutability, synchronization primitives, data
  races-as-tests via property-based / fuzz.

## Distributed bug

The bug spans services or components:

1. **Trace the request end-to-end** — OTel trace viewer, Jaeger,
   Honeycomb.
2. **Find the span with the anomaly** — long duration, error,
   missing.
3. **Pivot by correlation ID** — grep logs across services for
   the ID.
4. **Reproduce in a smaller scope** — local docker-compose with
   representative topology.

Observability: instrumentation must be in place beforehand (see
`monitoring-expert`).

## Heisenbugs

The bug disappears when observed.

Causes:

- Timing — print slows a thread enough to avoid a race.
- Optimization — debug build lacks -O2, no aliasing bugs.
- Instrumented monitors — profilers alter timing.

Techniques:

- Use sampling profilers (py-spy, async-profiler) — attach
  without altering the process.
- Use eBPF (bpftrace) — observe from the kernel without touching
  the process.
- Log after-the-fact — accept that observing may change timing
  and plan accordingly.

## Production debugging etiquette

- **Announce** — in the ops channel; coordinate with on-call.
- **Prefer read-only tools** — samplers, core dumps, dumps to
  side, not debuggers attached live unless necessary.
- **Never attach breakpoints in prod** — single-stepping pauses
  the process.
- **Capture then leave** — thread / heap dump, then detach.
  Analyze offline.
- **Leave no trace** — remove ad-hoc instrumentation after.
- **Post-mortem** — share what you learned; update runbook.
