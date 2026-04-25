# Lifecycle phases — heuristics, edge cases, routing

The conductor recognizes five phases. Each has a deterministic detection
recipe and a default routing decision. Use these heuristics first, LLM
judgment second.

---

## 1. Greenfield

**Definition.** New project. Either nothing has been written yet or the
codebase is mostly README, scaffolding, and `hello world`.

**Detection (any two of):**

- `git log --oneline | wc -l` ≤ 3 commits.
- No `tests/`, `test/`, `__tests__/`, `spec/`, or equivalent directory has
  any non-trivial files.
- No package manifest with real dependencies (an `npm init -y`-style
  `package.json` with no deps still counts as greenfield).
- No CI workflow files in `.github/workflows/`, `.gitlab-ci.yml`,
  `.circleci/`, etc.
- More README/docs lines than code lines.

**Edges:**

- A "greenfield" repo with a 5,000-line `prototype.py` is **not**
  greenfield — it's already in *building* with bad structure.
- An empty repo with a 2-page `SPEC.md` is greenfield. The spec is the seed.

**Default driver.** `feature-forge` if no spec exists. `architecture-designer`
if the spec is written but the system shape isn't. `tdd` if specs and
shape exist and the user wants to start writing.

**Common companions.** `api-designer`, `architecture-designer`,
`fullstack-guardian`.

**Conductor handoff line.**

> "Greenfield repo, no spec yet. Want me to run a feature-forge interview to
> turn this into a buildable spec, or do you have one in mind already?"

---

## 2. Building

**Definition.** Active development. Tests are growing, commits are regular,
no production tag yet — or the first one is days away.

**Detection (any two of):**

- 4-200 commits.
- Test directory exists and has more than placeholder files.
- Dependencies are non-trivial (real frameworks, not just lint).
- CI exists and (mostly) passes.
- Last commit within the last 7-14 days.
- No git tags or only `v0.x` / pre-release tags.

**Edges:**

- A repo with 200 commits but no tests is *not* building — it's *maintenance*
  in disguise. Surface this to the user before routing.
- A repo with one big "initial commit" of 50 files and then nothing for
  months is *greenfield-stalled*, not building.

**Default driver.** `ship` for "let's get this shipped today" tasks. `tdd`
when the user is writing tests first. `feature-forge` if a *new* feature
needs scoping inside the building project.

**Common companions.** `pr-review`, `commit`, `refactor`, `debug-fix`,
plus the relevant domain skill (`react-expert`, `postgres-pro`, etc.).

**Conductor handoff line.**

> "Building phase — N commits, M tests, last activity X days ago. Default
> driver is `ship`. What's the next thing you want to land?"

---

## 3. Established

**Definition.** Production code. There's a release tag, regular maintenance
commits, healthy CI. Architecture is stable; people use this thing.

**Detection (any two of):**

- One or more `v1+` git tags.
- More than 200 commits, or more than 6 months of history.
- A non-trivial CI pipeline that runs on PRs and main.
- Test suite that exercises the public API, not just unit-tested internals.
- A `CHANGELOG.md` that's actually maintained, or releases on the package
  registry.
- Multiple contributors over time (`git shortlog -sn` has more than one name).

**Edges:**

- A v1.0 repo with no commits in 6 months is *established → maintenance*.
  Surface that.
- A monorepo where one package is established and another is greenfield is
  multi-phase. Operate per-package, not per-repo.

**Default driver.** Task-dependent. The conductor offers a routing menu:

- "Add a feature" → `feature-forge`, then `ship`.
- "Fix a bug" → `debug-fix`.
- "Refactor X" → `refactor` (or `legacy-modernizer` if the area is fragile).
- "Review this PR" → `pr-review`.
- "Add tests for X" → `test-master`.
- "Investigate prod issue" → `debugging-wizard` + `sre-engineer`.

**Common companions.** Domain skill always (`react-expert`, `postgres-pro`,
`kubernetes-specialist`, …). `pr-review` is the default for any change
worth landing.

**Conductor handoff line.**

> "Established codebase — v{X.Y.Z}, healthy CI, last release N days ago.
> What are we working on today?"

---

## 4. Maintenance

**Definition.** A real system that nobody is actively building on, but that
still runs and still has to be touched occasionally. Bug fixes, dependency
bumps, security patches, the occasional small feature.

**Detection (any two of):**

- Last meaningful (non-bot, non-`chore: bump deps`) commit > 90 days ago.
- Sparse test coverage relative to size, or tests that haven't been
  updated alongside code.
- Outdated dependencies (a quick scan finds things several majors behind).
- Few or no PRs in the last quarter.
- README still references "TODO" / "WIP" sections that have been there for
  years.

**Edges:**

- "Maintenance" with a healthy test suite and modern deps is just *quiet
  established*. Don't pathologize it.
- A repo that *should* be in maintenance but is being actively rewritten
  in place is actually in *migration*.

**Default driver.** `legacy-modernizer`. Even small changes here need
characterization tests and seams; don't let the user "just patch it".

**Common companions.** `spec-miner` (recover the original intent),
`test-master` (build characterization tests before changing anything),
`debug-fix` (when reality bites), `the-fool` (sanity-check assumptions
that may have rotted).

**Conductor handoff line.**

> "Maintenance phase — last real work N months ago, test coverage looks
> thin, deps are stale. I'd recommend `legacy-modernizer` even for small
> changes here. Want a spec-miner pass first to recover the original
> intent, or do you have a specific change in mind?"

---

## 5. Migration

**Definition.** A modernization is in flight. There are *parallel
implementations* of the same thing (`auth_v1.py` and `auth_v2.py`,
`/api/legacy/` and `/api/v2/`), feature-flag clusters gating new paths,
or a "rewrite branch" that's being merged piecewise.

**Detection (any two of):**

- Files matching `*_v2.*`, `*_new.*`, `*_legacy.*` clusters.
- Feature-flag library in use (LaunchDarkly, Unleash, Flagd, custom) with
  flags whose names suggest migration (`use_new_X`, `legacy_Y_enabled`).
- Two parallel API versions live (`/v1/` and `/v2/`) with overlapping
  surface area.
- Active branches named `migration/*`, `rewrite/*`, `*-modernization`.
- Recent commits mention "strangler", "parity", "deprecate", "shim".

**Edges:**

- A repo with a single `_v2` file and no other migration signals is just
  someone's experiment. Don't classify the whole repo as migration.
- A migration that stalled (no commits in 90+ days on the migration files)
  has degraded to *maintenance with technical debt*. Worth surfacing.

**Default driver.** `legacy-modernizer` (Strangler Fig, Parallel Change,
parity verification — exactly what's needed mid-migration).

**Common companions.** `chaos-engineer` (verify the new path under
failure), `pr-review` (every migration step gets reviewed), domain skill
for the technology being migrated to.

**Conductor handoff line.**

> "Migration in flight — looks like {X} → {Y} (parallel paths in
> {paths}, feature flags {flags}). `legacy-modernizer` is the right
> driver. Where in the migration are you — adding a new strangler step,
> verifying parity, or deprecating the old path?"

---

## Disambiguation table

When two phases look plausible, here's how to break the tie:

| Both look like... | Decide by |
|---|---|
| Greenfield vs Building | If any code does real work, it's building. |
| Building vs Established | First production tag = established. |
| Established vs Maintenance | Last meaningful commit > 90 days ago = maintenance. |
| Maintenance vs Migration | Migration files actively changing = migration. Stalled migration files = maintenance. |
| Established vs Migration | Both can be true; treat the migrated area as migration and the rest as established. Operate per-area. |

If after this you still can't tell, **ask the user**. One sentence:

> "I see signals for both X and Y. Which feels right to you?"

Then commit and move on. Don't litigate.

---

## Multi-area projects

Large repos can have multiple phases at once: a stable `core/` (established),
an in-flight `auth/v2/` (migration), and a brand-new `experimental/` (greenfield).

The conductor handles this by **scoping the phase to the area being worked
on**, not the whole repo. When the user says *"let's work on auth"*, run
the heuristics on `auth/`. When they say *"let's start the experimental
plugin"*, run them on `experimental/`.

`.claude/project-state.md` can record per-area phases under a
`## Areas` section if the multi-phase pattern is durable. Don't pre-emptively
do this for two-area repos — only when it's actually useful.
