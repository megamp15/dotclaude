# Process state: attaching, dumping, inspecting

Techniques for inspecting a live or crashed process without
modifying its source.

## Identifying the target

```bash
ps auxf | grep <name>
pgrep -f <pattern>
lsof -p <pid>                      # open files / sockets / mmaps
lsof -i :8080                      # who's on this port
cat /proc/<pid>/status             # state, threads, VmRSS, etc.
cat /proc/<pid>/limits             # rlimits
cat /proc/<pid>/maps               # memory regions
ls -l /proc/<pid>/fd               # open fds
cat /proc/<pid>/cmdline | tr '\0' ' '
```

`/proc` is gold on Linux.

## Thread / stack dumps

### Python

```bash
# py-spy (pure Python; safe for prod; no code changes)
pip install py-spy
py-spy dump --pid <pid>                              # one-shot stacks
py-spy top --pid <pid>                               # top-like, sampling
py-spy record --pid <pid> -o flame.svg --duration 30 # flame graph
```

`py-spy` works on running processes and doesn't require restarting.

For async applications, `py-spy` shows coroutine states.

Alternative: `faulthandler.dump_traceback` in-process (requires
code change), or send SIGUSR1 to trigger a handler.

### Java / JVM

```bash
jstack <pid>                         # thread dump to stdout
jcmd <pid> Thread.print              # equivalent, more info
jcmd <pid> GC.heap_info              # heap summary
jcmd <pid> VM.flags                  # JVM flags
jcmd <pid> VM.native_memory summary  # NMT (if enabled)
```

`kill -3 <pid>` triggers a thread dump to stdout/stderr.

`async-profiler` for CPU and allocation profiling:

```bash
./profiler.sh -d 30 -f flame.html <pid>           # CPU
./profiler.sh -e alloc -d 30 -f alloc.html <pid>  # allocations
./profiler.sh -e wall -t -d 30 <pid>              # wall-clock
```

### Go

```bash
# Via net/http/pprof on /debug/pprof
curl -o cpu.pprof http://localhost:6060/debug/pprof/profile?seconds=30
curl -o heap.pprof http://localhost:6060/debug/pprof/heap
curl http://localhost:6060/debug/pprof/goroutine?debug=2   # all goroutines
go tool pprof -http=:0 cpu.pprof                            # web UI

# Or SIGQUIT for goroutine dump
kill -QUIT <pid>
```

### Node.js

```bash
# Live inspector (listens on --inspect port)
node --inspect=127.0.0.1:9229 app.js
# then chrome://inspect

# Heap snapshot
kill -USR2 <pid>                                 # if heap snapshot handler installed
# or via inspector + DevTools

# Continuous profiling
npm install 0x
0x -- node app.js                                # flame graph
clinic doctor -- node app.js                     # overall diagnosis
clinic flame -- node app.js
```

### .NET

```bash
dotnet-counters ps                               # list processes
dotnet-dump collect -p <pid>                     # full dump
dotnet-dump analyze <dump>
dotnet-gcdump collect -p <pid>                   # GC heap only
dotnet-trace collect -p <pid>                    # CPU / events
dotnet-stack report -p <pid>                     # stacks
```

Or Perfview on Windows.

### Rust

Usually via `gdb` / `lldb` directly. `cargo flamegraph` for
sampling CPU profiles. `tokio-console` for async Tokio runtime.

### C / C++

```bash
gdb -p <pid>
(gdb) thread apply all bt         # all thread backtraces
(gdb) info threads
(gdb) thread <n>
(gdb) bt full                     # with locals
(gdb) generate-core-file /tmp/dump.core   # take snapshot
(gdb) detach
```

`perf top -p <pid>` for sampling without pausing.

`lldb` is the equivalent on macOS.

## Heap dumps and analysis

### JVM

```bash
jmap -dump:format=b,file=heap.hprof <pid>     # live heap to file
jcmd <pid> GC.heap_dump /tmp/heap.hprof       # equivalent
```

Analyze with:

- **Eclipse MAT** — best for leak-suspect reports ("Find Leak
  Suspects").
- **VisualVM** — free, interactive.
- **YourKit** / **JProfiler** — commercial.

Key operations:

- **Histogram** — class counts / sizes.
- **Dominator tree** — objects responsible for retaining memory.
- **GC roots** — why is this object not collected?

### Python (memray)

```bash
pip install memray
memray run myscript.py                 # creates memray-<pid>.bin
memray flamegraph memray-<pid>.bin     # flame graph
memray table memray-<pid>.bin          # top allocating locs
memray tree memray-<pid>.bin           # retention tree
memray attach <pid>                    # attach to running process (limited)
```

Or `tracemalloc` in-process:

```python
import tracemalloc
tracemalloc.start(25)          # 25 frame stacks
# ... run workload ...
snap = tracemalloc.take_snapshot()
for stat in snap.statistics("lineno")[:10]:
    print(stat)
```

### Go

```bash
curl -o heap.pprof http://localhost:6060/debug/pprof/heap
go tool pprof -http=:0 heap.pprof
# In the UI: top, web, list <func>
```

Diff two snapshots to find growth:

```bash
curl -o heap1.pprof http://localhost:6060/debug/pprof/heap
# wait / run load
curl -o heap2.pprof http://localhost:6060/debug/pprof/heap
go tool pprof -base heap1.pprof heap2.pprof
```

### Node.js

```bash
# via --heapsnapshot-signal=SIGUSR2
node --heapsnapshot-signal=SIGUSR2 app.js
kill -USR2 <pid>                          # writes .heapsnapshot
# Load in Chrome DevTools → Memory → Load
```

Compare two snapshots (Comparison view) to find retainers.

## Core dumps

### Enabling

```bash
ulimit -c unlimited                 # current shell
echo "core.%e.%p" > /proc/sys/kernel/core_pattern
# In systemd: LimitCORE=infinity in unit
# In Docker: --ulimit core=-1 and mount a volume
```

### Generating

Crash produces one automatically. To capture live:

```bash
gcore -o /tmp/dump <pid>           # non-destructive snapshot
# kernel: kill -QUIT for some runtimes; kill -SEGV -o /tmp/dump for crash dump
```

### Analyzing

```bash
gdb <binary> <core>
(gdb) bt
(gdb) info threads
(gdb) thread apply all bt full
```

Strip binaries make this painful — keep debug info. Linux
distros typically provide `-debuginfo` packages; store the
original binary + source map.

## Post-mortem checklist

When you have a core / heap dump:

- [ ] Which thread crashed / allocated most?
- [ ] What's on the stack at the moment of interest?
- [ ] What are the arguments / locals?
- [ ] What's in memory near the fault (e.g., `x/16xw $rsp`)?
- [ ] What signal was received (`p $_siginfo`)?
- [ ] What's the list of objects in heap (histogram)?
- [ ] Who retains them (dominator tree)?

Document findings alongside the artifact so future investigators
don't redo your work.

## Attaching to production safely

Sampling profilers (`py-spy`, `async-profiler`) perturb very
little and are safe in prod.

Debuggers (`gdb`) **pause** the process — risky in prod.

eBPF tools (bpftrace, bcc) observe kernel-level events without
pausing the target.

Rule of thumb:

- **Read-only sampling** → OK in prod.
- **Pausing** → staging only, or coordinated maintenance.
- **Modifying state** (evaluating expressions that mutate) →
  never in prod.

## Recipes

### Find who's using port X

```bash
sudo lsof -i :8080
sudo ss -ltnp | grep 8080
```

### Count threads on a process

```bash
ps -eLf | awk '$2 == <pid>' | wc -l
cat /proc/<pid>/status | grep Threads
ls /proc/<pid>/task | wc -l
```

### Identify which syscall a process is stuck in

```bash
cat /proc/<pid>/stack       # kernel stack (requires CONFIG_STACKTRACE)
cat /proc/<pid>/wchan       # what the kernel is waiting on
```

### Find open file descriptors

```bash
ls -l /proc/<pid>/fd
lsof -p <pid>
```

### Spot growing FD count (socket leak)

```bash
watch -n 1 "ls /proc/<pid>/fd | wc -l"
```
