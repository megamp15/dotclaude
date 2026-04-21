# Strangler Fig, seams, and parallel change

The patterns that make it possible to change legacy systems
without freezing feature work.

## Strangler Fig (Fowler)

Named after vines that grow around trees until the tree rots
away, leaving the vine as the structure.

### Shape

```
+---------+       +---------+       +---------+
| Clients |  -->  | Facade  |  -->  | Legacy  |
+---------+       +---------+       +---------+
                       |
                       +------------>   New impl (built piece by piece)
```

### Steps

1. **Introduce a facade / shim** between clients and the
   legacy system. Initially pass through 100% of calls.
2. **Build new functionality in the new system.** Facade routes
   specific calls (per-endpoint, per-user, per-tenant) to the
   new one.
3. **Gradually move traffic.** A use case at a time; verify; move
   on.
4. **Delete legacy** when it has 0% traffic.

### Granularity

The facade can live at many levels:

- **API gateway** — HTTP routing by path prefix.
- **Process layer** — in-process router.
- **Module** — within a monolith, a new package gradually steals
  calls from the old one.
- **Function** — feature flag inside the function dispatches.

Choose the coarsest level where you can still slice. Coarser =
simpler.

### Parity verification

Until the new path is trusted, run **both**:

- **Dual invocation** — call old and new; log diffs.
- **Response-comparison canary** — old is authoritative; new's
  output is compared and discrepancies reported.

Track a parity metric; don't cut over until it's > 99.99% over
N days.

### Rollback

Facade has a knob per route: `old | new | both (compare)`. Flip
back to `old` at any time.

## Seams (Michael Feathers)

> A seam is a place where you can alter behavior in your
> program without editing in that place.

You can't test code that has no seams. Legacy code often has
none — constructors create their dependencies, globals are
read, files are opened directly.

### Types

- **Object seams** — subclass and override.
- **Link seams** — swap a library at link/load time.
- **Preprocessor seams** — C/C++ `#ifdef`, Java annotation
  processing.
- **Interface seams** — depend on an interface, swap impls.

### Introducing a seam

Two common techniques from *Working Effectively with Legacy
Code*:

1. **Sprout Method / Class** — add a new method or class for the
   new logic; call it from the legacy code. Old code is
   untouched; new code is tested.

   ```python
   # Legacy
   def process_order(order):
       # ... 200 lines ...
       for item in order.items:
           price = calculate_price(item)          # legacy logic
           apply_price(order, item, price)
       # ... more ...

   # After sprout
   def process_order(order):
       # ... 200 lines ...
       for item in order.items:
           price = calculate_price_v2(order, item)  # new, tested
           apply_price(order, item, price)
       # ... more ...
   ```

   The new function is testable in isolation; legacy remains
   untouched but uses it.

2. **Extract and Override** — pull a chunk of logic out into a
   method, make it overridable (extract interface / virtual),
   then you can test or swap it.

### Dependency injection retrofit

Pure DI isn't required; passing the dependency as a parameter
works:

```python
# Before: hard-coded dependency
def save_user(user):
    db = MySQLClient.get()       # global, hard to test
    db.execute("INSERT ...")

# After: parameter with default
def save_user(user, db=None):
    db = db or MySQLClient.get()
    db.execute("INSERT ...")
```

Now tests can pass a fake `db`. Production behavior unchanged.

## Branch by Abstraction (Fowler)

When a big change would require a long-lived branch, do it on
trunk with an abstraction layer.

### Steps

1. Introduce an abstraction (interface) in front of the thing
   you want to replace.
2. Route all callers through the abstraction. Current impl is
   behind it.
3. Build the new impl behind the same abstraction.
4. Flip callers to the new impl one by one (or all at once via
   factory).
5. Remove the old impl.
6. Optionally, remove the abstraction if no longer needed.

### Example: swapping message queue

```
before:  Publisher -> RabbitMQ
mid:     Publisher -> QueueAbstraction -> RabbitMQ   (no behavior change)
         Publisher -> QueueAbstraction -> Kafka      (new path)
after:   Publisher -> QueueAbstraction -> Kafka
         (Rabbit impl deleted; abstraction may be kept or inlined)
```

Each step is a small PR. Trunk stays deployable.

## Parallel Change (expand / contract)

For changing an interface or schema.

### Three phases

1. **Expand** — add the new shape alongside the old. Both exist.
2. **Migrate** — update callers / readers one by one to the new
   shape.
3. **Contract** — remove the old shape once nothing uses it.

### Example 1: renaming a method

```python
class Order:
    def save(self):     # old
        ...

# Expand
class Order:
    def save(self):     # old, still works
        return self.persist()
    def persist(self):  # new, same behavior
        ...

# Migrate
# update callers: order.save() → order.persist()

# Contract
class Order:
    def persist(self):
        ...
```

### Example 2: splitting a database column

See `SKILL.md` core; expand columns, dual-write, backfill,
migrate reads, contract.

### Example 3: HTTP API field rename

```
Expand:   response { "name": "...", "display_name": "..." }
Migrate:  clients adopt "display_name" over N weeks
Contract: remove "name"
```

Announce a deprecation window; track clients still sending the
old field via logging.

## Dark launching

Ship new code in production, but its effects are invisible until
you trust it.

Techniques:

- **Shadow traffic** — new path receives the same input, results
  discarded (or compared).
- **Feature flag off** — code exists, doesn't execute.
- **Write to /dev/null** — e.g., new pipeline writes to a table
  no one reads.
- **Invisible UI change** — CSS hides the new thing.

Why it's powerful: you're collecting data on the new code
*under real load* before anyone depends on it.

## Traffic mirroring

Duplicate production traffic to staging or a new service. Do not
mutate external systems from the mirrored path.

- **Service mesh** — Istio, Linkerd support mirror/teeing out of
  the box.
- **Load balancer** — NGINX `mirror` directive, Envoy.
- **App layer** — a goroutine / task that fires-and-forgets a
  copy.

Use cases:

- Pre-rollout performance testing with real data.
- Parity check for a rewrite.
- Stress test on a candidate.

## Incremental rollout controls

For any cut-over, use a gate:

```
# traffic split over time
t0:   0% new / 100% old
t+1d: 1% new
t+3d: 10% new (if parity + error metrics OK)
t+1w: 50% new
t+2w: 100% new
```

Automate the ramp if you can — with metrics guards that pause or
reverse on anomaly.

## Combining these

A real modernization stacks all of them:

- **Branch by Abstraction** around the component to change.
- **Strangler Facade** directs calls.
- **Parallel Change** for every API-shape change inside.
- **Dark launch** the new impl.
- **Mirror traffic** for parity.
- **Ramp rollout** over days to weeks.
- **Delete** the old code and abstraction when done.

Each layer is insurance; each is reversible.

## When not to use Strangler / incremental

- **Tiny system** — smaller than your PR to introduce a facade;
  just rewrite it in a weekend.
- **No tests, no understanding, no observability** — fix those
  preconditions first, or a rewrite isn't any riskier than
  incremental.
- **Different problem** — this is about evolution. Greenfield or
  full isolation is a different decision.
