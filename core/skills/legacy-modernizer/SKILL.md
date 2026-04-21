---
name: legacy-modernizer
description: Evolving legacy code without rewriting it — characterization tests, seams, the Strangler Fig pattern, incremental migration (framework, language, database), backfills, feature parity verification, and the discipline of leaving systems healthier than found. Distinct from greenfield work and full rewrites.
source: core
triggers: /legacy-modernizer, legacy code, refactor legacy, strangler fig, characterization test, golden master, technical debt, incremental migration, framework upgrade, database migration, decommission, rewrite risk, feature parity, feature flag migration
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/legacy-modernizer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# legacy-modernizer

Incremental evolution of legacy systems. Activates when you need
to change code you don't fully trust, without a rewrite.

> **See also:**
>
> - `core/skills/refactor/` — smaller-scale refactors
> - `core/skills/test-master/` — characterization tests, mutation
> - `core/skills/debug-fix/` — when legacy bites back
> - `core/skills/the-fool/` — sanity-check assumptions

## When to use this skill

- Inherited code with few tests and no clear owners.
- Need to add a feature to a fragile area.
- Migrating a framework (Angular 1→17, Django 1→5, Rails 4→7).
- Swapping a database (MySQL → Postgres, SQL → DocumentDB).
- Replacing a messaging backbone.
- Decomposing a monolith into services.
- Retiring a system that's still handling traffic.
- Upgrading the language / runtime (Node 14 → 22, Python 3.8 →
  3.12, Java 8 → 21).

## When *not* to use this skill

- You legitimately have green field. Just build it with
  `core/skills/feature-forge/`.
- The system is tiny and rewriting is genuinely faster than
  characterizing + evolving.
- You have no observability at all and no way to build any.
  Modernize *observability* first (`monitoring-expert`), then
  touch code.

## References (load on demand)

- [`references/strangler-and-seams.md`](references/strangler-and-seams.md)
  — Strangler Fig pattern, seams (Feathers), Branch by
  Abstraction, Parallel Change (expand/migrate/contract), dark
  launching, traffic mirroring, and incremental rollouts.
- [`references/characterization-and-safety.md`](references/characterization-and-safety.md)
  — characterization tests, golden-master / approval testing,
  snapshot strategy, mutation testing on legacy, property-based
  "backstops", production-recorded test data, and automated
  baseline capture.

## Core principles

1. **Don't rewrite if you can evolve.** Rewrites famously miss
   hidden invariants; most fail.
2. **Characterize before changing.** Pin current behavior with
   tests before you touch a single line.
3. **Create seams.** Legacy code rarely has dependency
   injection. Introduce seams (wrapper, adapter, interface) at
   the boundary of the change.
4. **Small, reversible steps.** Each PR should be shippable and
   deployable. No 6-month branches.
5. **Ship behind flags.** Parallel run old and new code; flip
   traffic gradually.
6. **Verify parity with traffic, not tests alone.** Shadow the
   new path; diff outputs vs. old for a period.
7. **Cut over, then delete.** Leaving both paths indefinitely
   means two systems to maintain. Commit to deletion.
8. **Leave campground cleaner than found.** Boy Scout Rule.
   Update a comment, add a test, rename a misleading variable
   every time you're in a file.

## Defaults

| Question | Default |
|---|---|
| Start of any legacy change | Characterization tests first |
| Seam technique | Extract interface / wrapper class |
| Big change pattern | Strangler Fig (facade routes to new impl) |
| Verification | Shadow traffic + diff; cut over after N days |
| Rollout | 1% → 10% → 50% → 100%, with metrics gates |
| Rollback plan | Feature flag flip; keep old path compiled for 30d |
| Dependencies | Freeze + upgrade one at a time; avoid simultaneous |
| Deletion | Scheduled within the modernization project, not "later" |
| Database migration | Expand → dual-write → backfill → dual-read → contract |
| Framework upgrade | Strangler modules, not big-bang |

## Anti-patterns

- **Big bang rewrite.** The legend of the successful big-bang
  rewrite is mostly that — legend.
- **"Freeze everything" during migration.** Organizational
  pressure to ship features doesn't vanish; parallel paths are
  better than a freeze.
- **Untested refactor.** Changing code you don't understand
  without tests is gambling.
- **Touching the dragon to "clean it up"** with no concrete
  business need. Legacy code you don't need to change is fine.
- **Leaving dual paths indefinitely.** You double the surface
  area and the bugs.
- **Rewriting without parity tests.** If you can't measure
  equivalence, you'll find out when customers do.
- **Upgrading through too many versions at once.** Jump one or
  two majors; read migration notes; run tests in between.
- **Heroic solo modernization.** Changes of this size need at
  least one other reviewer who understands the domain.

## Output format

For a modernization plan:

```
System:         <name>
Current state:  <framework / language / state>
Target state:   <what you're moving to>
Constraint:     <zero downtime / zero parity loss / etc.>

Phases:
  1. Observability + baseline metrics
  2. Characterization tests around the change zone
  3. Seams introduced; old path abstracted
  4. New path built behind flag
  5. Shadow traffic + parity verification (N days)
  6. Gradual rollout
  7. Old path deleted
  8. Post-migration cleanup (dead config, stale docs, orphaned
     feature flags)

Exit criteria per phase:
  ...

Rollback: at every phase, feature flag flip reverts to old.
```

For a code-level migration within a file / module:

```
Change goal: <business outcome>
Parallel Change steps:
  Expand:   <new interface / column / method added; no callers>
  Migrate:  <callers switched one at a time>
  Contract: <old removed once no callers remain>

Tests:
  Characterization: <tests added before changes>
  New behavior:     <tests of the target>

Deletion ticket: <jira/linear link; must be closed this quarter>
```

## The Strangler Fig in one picture

```
     Client
       |
       v
   +-------+        (new requests route here over time)
   | Facade|
   +---+---+
       |-----------------+
       v                 v
  +--------+       +-----------+
  | Legacy |       | New impl  |
  +--------+       +-----------+
```

Start with facade routing 100% to Legacy. Move a use case at a
time to New. Delete Legacy when 0% traffic.

## Parallel Change (expand / contract)

The single most useful incremental technique. Example: changing
a database column `name` → separate `first_name` / `last_name`.

1. **Expand** — add `first_name` + `last_name` columns. Populate
   them alongside `name` on write; don't change readers yet.
2. **Migrate writes** — switch writes to the new columns;
   maintain `name` in sync via trigger or app logic.
3. **Backfill** — populate new columns for historical rows.
4. **Migrate reads** — switch readers to the new columns.
5. **Contract** — remove `name` writes; drop the column.

Each step is reversible. Stop after any step and you're in a
known state.

## Characterization tests

**Goal**: pin current behavior — bugs included — before change.

Steps:

1. Pick inputs (from prod logs ideally).
2. Record current output.
3. Add a test that asserts current output for each input.
4. Tests now pass. Don't change code yet.
5. When you refactor, test failures tell you you changed
   observable behavior.

Tools:

- **Approval tests** — library captures output; diff against
  golden file.
- **Snapshot tests** — framework-specific (Jest, pytest-
  snapshot).
- **Production log replay** — record request/response pairs,
  replay in test.

## Framework upgrade pattern

Moving Django 1.11 → 5.0? Don't do it in one jump.

1. **Get on the latest patch of current major** — free bug fixes.
2. **Upgrade one major at a time** — read changelog for
   deprecations; fix deprecation warnings at the *current* major
   so the next jump is smaller.
3. **Run full test suite at each major.** Promote the flakiest
   tests or add missing ones.
4. **Upgrade dependencies between jumps** — many are coupled to
   framework version.
5. **Treat each jump as its own rollout** — deploy, monitor,
   stabilize, then start the next.

## Database migration pattern

See Parallel Change above. Full pattern for changing a table:

1. **Expand** — add new columns / tables; keep old.
2. **Dual-write** — app writes to both.
3. **Backfill** — migrate historical data in batches.
4. **Dual-read with preference** — app reads old; shadows with
   new; diffs and logs mismatches.
5. **Switch reads** — app reads new; may still write both.
6. **Contract** — stop writing old; drop after retention window.

Never drop and rebuild in one deploy. Never.

## Decommission playbook

Retiring an old system fully:

1. **Inventory callers** — logs, API gateway, service registry,
   codebase grep.
2. **Route callers off** — for each caller: migrate, deprecate,
   shut off.
3. **Announce a date** — with enough lead time for stragglers.
4. **Black-hole test** — route 1% of traffic to a 410 Gone
   response. If no one notices, route more.
5. **Freeze the system** — read-only, no new users.
6. **Migrate historical data** — archive what must be kept;
   delete what doesn't need to survive.
7. **Shut down** — after a grace period.
8. **Delete infra + code + docs + dashboards + alerts + feature
   flags + rate limits + DNS entries.** Anything left behind
   will haunt whoever follows.

## Modernization metrics

Track while modernizing:

- **Parity rate** — % of old/new outputs that match under shadow.
- **Traffic on new path** — % of requests hitting the new impl.
- **Latency delta** — new p99 − old p99.
- **Error rate delta** — new − old.
- **Code removed per week** — modernization should shrink code,
  not grow it permanently.
- **Deprecation tickets aged** — track backlog of "kill me"
  debt; it shouldn't grow.

If any of these regress, slow or roll back.

## Two hard things

- **Understanding the system you're changing.** Budget
  generously for reading + interviews; pairs well with
  `core/skills/spec-miner/`.
- **Resisting the urge to rewrite "while you're in there".**
  Every file has five things you'd change; pick one. Ship. Move
  on.

## After the migration

- [ ] Old path deleted.
- [ ] Stale flags, configs, env vars removed.
- [ ] Dashboards / alerts for old path archived.
- [ ] Docs updated; ADR written about what and why.
- [ ] Retrospective: what went smoother than expected? What
      burned days? (Update this skill accordingly.)
- [ ] Knowledge spread: the person who did the work isn't the
      only one who understands the new system.
