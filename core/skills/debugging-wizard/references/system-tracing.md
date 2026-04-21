# System tracing: syscalls, perf, eBPF, distributed

When the bug isn't in your code — or you need to prove it isn't.
System-level observability: syscalls, kernel events, network,
distributed traces.

## strace / ltrace

`strace` — syscalls of a process.

```bash
strace -p <pid>                              # live attach
strace -p <pid> -f                           # follow forks/threads
strace -p <pid> -e trace=network             # only net syscalls
strace -p <pid> -e trace=openat,read,write   # IO
strace -p <pid> -T -tt                       # time per syscall + timestamps
strace -p <pid> -c                           # summary (counts + totals)
strace -p <pid> -o strace.log                # log to file
strace -f -e trace=%file ./prog              # track all file access in prog
```

`ltrace` — library calls.

```bash
ltrace -p <pid>
ltrace -e 'malloc+free' ./prog
```

Use strace to:

- Find what file the process can't open.
- See repeated EAGAIN / EINTR loops.
- Measure syscall latency (`-T`).
- Discover unexpected syscalls (e.g., `connect` to an unexpected
  host).

**Overhead**: non-trivial. On a hot process, strace can slow
things 10×. Prefer eBPF (below) in prod.

## perf (Linux)

```bash
perf top -p <pid>                                    # live hot functions
perf record -F 99 -p <pid> -g -- sleep 30            # 30s profile
perf report                                          # interactive
perf script | ./FlameGraph/stackcollapse-perf.pl | \
  ./FlameGraph/flamegraph.pl > flame.svg             # flame graph
```

Perf events beyond CPU:

```bash
perf stat -e cache-misses,cache-references,page-faults,context-switches ./prog
perf trace -p <pid>                                  # perf's strace
```

## ftrace

Kernel function tracer. Usually accessed via `trace-cmd`:

```bash
trace-cmd record -p function_graph -g vfs_read
trace-cmd report
```

For low-level kernel debugging; less needed if you have eBPF.

## eBPF (bcc + bpftrace)

Programmable kernel observability without recompiling anything.

### bcc tools

Install `bcc-tools` / `bpfcc-tools` (name varies by distro).
Useful ones in `/usr/share/bcc/tools/`:

| Tool | What it shows |
|---|---|
| `execsnoop` | New processes |
| `opensnoop` | File opens |
| `biolatency` | Block I/O latency histogram |
| `biosnoop` | Per-I/O details |
| `tcplife` | TCP session durations |
| `tcpconnect` | Outbound connects |
| `tcpaccept` | Inbound accepts |
| `tcptracer` | Connect/accept/close |
| `tcpretrans` | Retransmits |
| `udpflow` | UDP send/recv |
| `runqlat` | Scheduler latency |
| `offcputime` | Time off-CPU (waiting) by stack |
| `offwaketime` | Off-CPU + waker stack |
| `profile` | CPU profiler → flame graph |
| `argdist` | Aggregate function args |
| `funclatency` | Latency of a function |
| `memleak` | Outstanding allocations by stack |

Example:

```bash
# What's the p99 block I/O latency this minute?
biolatency 60 1
# Which process is opening what, right now?
opensnoop
# Flame graph of CPU, 30 seconds
profile -F 99 --folded 30 > out.stacks
./FlameGraph/flamegraph.pl out.stacks > flame.svg
# Who is re-transmitting?
tcpretrans
# Why is my app blocked?
offcputime -p <pid> 10 > off.stacks
```

### bpftrace

Small language for custom probes:

```bpftrace
// Histogram of write(2) sizes
bpftrace -e 'tracepoint:syscalls:sys_enter_write { @sz = hist(args->count); }'

// TCP retransmits per remote IP
bpftrace -e 'kprobe:tcp_retransmit_skb { @[ntop(sk->__sk_common.skc_daddr)]++; }'

// All openat() by a specific pid
bpftrace -e 'tracepoint:syscalls:sys_enter_openat / pid == 12345 / { printf("%s %s\n", comm, str(args->filename)); }'
```

eBPF is preferred to strace in prod — overhead is ~0 when the
probe isn't firing.

## Continuous profiling

Always-on sampling profilers write to a time-series store so you
can diff past versus present.

- **Parca** — open source; eBPF-based.
- **Pyroscope** — Grafana Labs; multi-language.
- **gProfiler** — Granulate; many languages unified.
- **Datadog Continuous Profiler** — commercial.
- **Polar Signals Cloud** — hosted Parca.

Integrate once; the next perf mystery is already solved when it
happens.

## Network debugging

### tcpdump / Wireshark

```bash
# Capture
sudo tcpdump -i any -w dump.pcap 'port 5432 and host db.local'

# Analyze
wireshark dump.pcap
tshark -r dump.pcap -Y 'http.response.code >= 400'
```

Tips:

- Use `-s 0` to capture full packets.
- Rotate with `-C 100 -W 10`.
- Filter at capture time if volume high (`'tcp port 80'`).

### ss / netstat

```bash
ss -tnlp             # listening TCP + owning process
ss -tn state established
ss -i                # per-socket info (rtt, cwnd, retransmits)
ss -s                # summary
```

### mtr / traceroute

```bash
mtr --report -c 100 api.example.com   # live packet loss + latency
traceroute api.example.com
```

### curl + `-w`

```bash
curl -so /dev/null -w "dns %{time_namelookup} conn %{time_connect} ssl %{time_appconnect} ttfb %{time_starttransfer} total %{time_total}\n" \
  https://api.example.com/
```

Quick phase timing without heavy tools.

## I/O debugging

```bash
iotop -oP                       # which processes are doing I/O
iostat -xz 1                    # device-level I/O
vmstat 1                        # pressure: si/so, bi/bo, cs, us/sy/wa/id
pidstat -d 1                    # per-pid I/O bytes
dstat -tcdngy 1                 # combined, human-readable (if installed)
```

Look for:

- `wa` column in vmstat/top climbing → I/O wait bottleneck.
- High `bi`/`bo` → heavy read/write.
- `swap in/out` (`si`/`so`) > 0 → memory pressure.

## Disk space and inode exhaustion

```bash
df -h                           # human readable space
df -i                           # inodes
du -sh /var/* | sort -h | tail  # what's big in /var
ncdu /                          # interactive disk usage
```

Common outage: log file filled the disk; nothing obvious because
`du` on the mount is small because the file is still open and
the OS hasn't freed the inode. `lsof +L1` finds deleted-but-open
files.

## CPU: per-CPU, context switches

```bash
mpstat -P ALL 1                 # per-CPU busy
pidstat -wt 1                   # per-thread context switches
vmstat 1                        # cs column
```

Very high `cs` = too many threads / contention.

## System-wide snapshot

```bash
# Brendan Gregg's "USE method" checklist in 60 seconds
uptime
dmesg -T | tail -n 50
vmstat 1 5
mpstat -P ALL 1 5
pidstat 1 5
iostat -xz 1 5
free -m
sar -n DEV 1 5
sar -n TCP,ETCP 1 5
```

Build this as `scripts/first-aid.sh` on every prod host.

## Distributed tracing for debugging

When the bug crosses services:

1. **Find a failing request's trace ID** — log search for the
   user's ID or the error text; grab the `trace_id` label.
2. **Open the trace** in Jaeger / Tempo / Honeycomb / whatever.
3. **Look for**:
   - Longest span → where the time went.
   - Spans with `status=ERROR` → exact failure location.
   - Missing spans (gap in the timeline) → service didn't emit or
     dropped span.
   - Unexpected fan-out (N+1) → perf root cause.
4. **Pivot to logs for that span** — instrumentation should
   correlate trace_id + span_id in logs.
5. **Reproduce locally** — single request with the same inputs,
   trace enabled, step through.

See `core/skills/monitoring-expert/references/logs-and-traces.md`.

## When to reach for which tool

| Question | Tool |
|---|---|
| What's my process spending time on? | Profiler (flame graph) |
| Which syscall is it stuck in? | strace / bpftrace |
| Why is I/O slow? | biolatency, iostat |
| Who's talking to whom on the network? | tcplife, ss, tcpdump |
| Why the retransmits? | tcpretrans |
| Is memory leaking? | Heap dump diff |
| Why off-CPU? | offcputime |
| Why is it slow across services? | Distributed trace |
| Why does it fail sometimes? | Continuous profiling + traces |
| Why did it crash? | Core dump + debugger |
| Why is behaviour different in prod? | eBPF + profilers attached in prod |

Start cheap. Escalate to heavier tools only when needed.
