# Characterization tests and safety nets

How to pin legacy behavior before touching it, and how to keep
the blanket of safety thick through a migration.

## Why characterize

A characterization test asserts **what the system does today**,
bugs and all. You are not asking "is this correct?" — you are
asking "what *is* the output for this input?" and locking it in.

Value:

- You get tests without needing specs.
- When you refactor, test failures tell you you changed
  observable behavior.
- Intentional behavior change becomes explicit: update the
  assertion with a comment about why.

## The basic recipe

1. **Pick inputs** — 5–50 to start; prefer real inputs (logs,
   DB snapshots, fixture files).
2. **Run the code**, capture the output.
3. **Assert**: given input X, output is Y (exactly).
4. **Don't fix bugs yet.** If the output is wrong, the test
   still pins "what it does now".
5. **Mark known bugs** in a comment:

   ```python
   def test_process_weird_edge_case():
       # NOTE: legacy bug — swallows the error and returns empty.
       # Preserved here to prevent accidental change; fix in ticket JIRA-1234.
       assert process(weird_input) == ""
   ```

## Approval / golden-master testing

Library captures actual output as a file; on next run, compares.
Diffs are either approved (accept the new "golden") or rejected.

Tools:

- **Python**: `approvaltests`, `pytest-snapshot`, `syrupy`.
- **JS/TS**: Jest `toMatchSnapshot`, `vitest snapshot`.
- **Java**: ApprovalTests, `assertj`'s `compareTo`.
- **.NET**: VerifyTests.
- **Rust**: `insta`.

Example (pytest-snapshot):

```python
def test_render_report(snapshot):
    report = render_report(fixture_data)
    snapshot.assert_match(report, "report.txt")
```

When expected changes:

```
pytest --snapshot-update
git diff tests/__snapshots__/  # review carefully
```

### Snapshot hygiene

- **Review snapshot diffs like code.** Auto-updates that no one
  reads are worse than no tests.
- **Keep snapshots small and specific.** Whole-page HTML
  snapshots churn constantly.
- **Deterministic output.** Scrub timestamps, random IDs, query
  ordering.

## Production-recorded test data

Best input corpus = real traffic.

Methods:

- **Request/response mirror** — capture N failing and N normal
  requests; replay.
- **DB snapshot** — restore into an isolated dev DB; run
  characterization tests against it.
- **Log-driven** — if logs capture input + output, extract.

PII handling:

- Strip or pseudonymize before committing to the repo.
- Or keep fixtures in a private bucket and download in CI via
  restricted credentials.

## Boundary coverage

When you can't test everything, test the boundaries:

- **Inputs that cause branching** — `if` conditions.
- **Error paths** — what does the code do on empty / null /
  invalid?
- **Scale edges** — 0 items, 1 item, 1000 items.
- **Time-dependent paths** — end of month, leap day, DST.
- **Concurrency** — if state is shared, test with multiple
  callers.

## Mutation testing on legacy

After adding tests, run mutation testing to check *whether your
tests actually catch changes*.

```bash
# Python
mutmut run --paths-to-mutate src/legacy.py
mutmut results

# JavaScript/TypeScript
npx stryker run

# Java
mvn pitest:mutationCoverage
```

Any surviving mutant = a gap in coverage. Especially valuable on
legacy code where coverage numbers lie.

## Property-based backstops

When you can describe what *should* be true regardless of input,
a property-based test finds corner cases.

```python
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_sort_preserves_length(xs):
    assert len(legacy_sort(xs)) == len(xs)

@given(st.lists(st.integers()))
def test_sort_is_sorted(xs):
    result = legacy_sort(xs)
    assert all(a <= b for a, b in zip(result, result[1:]))
```

If `legacy_sort` is broken on an edge case, Hypothesis will
usually find the minimal example.

See `core/skills/testing` strategy mode and `core/skills/testing/references/strategy-property-and-mutation.md`.

## Contract tests at boundaries

When rewriting a service, contract tests at HTTP / RPC
boundaries protect callers:

- **Consumer-driven contracts** (Pact) — consumers declare what
  they need; provider verifies.
- **Schema checks** — OpenAPI / AsyncAPI; linted in CI against
  previous version for breaking changes.
- **Snapshot responses** per endpoint.

## Safety rails during migration

### Feature flags

Every risky branch goes behind a flag:

```python
if flags.is_enabled("use_new_pricing_engine", user=user):
    return new_price(item)
return legacy_price(item)
```

Rules:

- **Every flag has an owner + delete-by date.** Track in a
  registry.
- **Delete flags once stable.** Rot worse than code rot.
- **Never nest flags more than 2 deep.** Nested flags produce
  cartesian test explosion.

### Canary + metrics gates

Roll out gradually with metric-based gates:

- Error rate must stay < 1% above baseline.
- p99 latency must stay < 1.2× baseline.
- Business metric (conversions, revenue) must not drop.

Automate the rollback if gates trip. Use Argo Rollouts, Flagger,
LaunchDarkly metric observers, or homegrown.

### Shadow and compare

```python
def get_user(id):
    old = legacy_fetch(id)
    if flags.is_enabled("shadow_new_fetch"):
        try:
            new = new_fetch(id)
            if not equal(old, new):
                logger.warning("parity mismatch", extra={"id": id, "diff": diff(old, new)})
        except Exception as e:
            logger.exception("shadow call failed", extra={"id": id})
    return old
```

Dashboard the mismatch rate. Cut over only when it's at your
target level.

### Kill switches

Beyond flags, a **global kill switch** per subsystem:

- Remote config `pricing.kill=true` disables the subsystem and
  falls back to last-known-good.
- Tested regularly — "does our kill switch still work?"

## Instrumentation before change

Before touching the code:

- **Add metrics** around the area: invocations, errors, latency.
- **Add traces** at entry/exit of the key functions.
- **Add log lines** at decision points (behind DEBUG level).

Now you can measure whether your migration improved or regressed
behavior. Without this baseline, parity is a feeling, not a
measurement.

## Rewrite equivalence testing

If you are rewriting a service:

1. **Record prod traffic** for N days (requests + responses).
2. **Scrub + replay** against the new service.
3. **Diff responses**:
   - Exact match → ideal.
   - Semantic match (JSON normalized, order-insensitive) → OK.
   - Mismatches → investigate.
4. **Track parity over time** as a real metric.

Only cut over when parity > your target SLO (99.99% for most,
higher for financial).

## Dangerous assumptions

- "**If tests pass, I didn't break anything.**" Unless the tests
  were designed to catch this change, they prove nothing.
- "**The old code handles this edge case.**" Read the code. Don't
  trust that it does.
- "**We'll delete the old path later.**" Later rarely arrives.
  Schedule the deletion now.
- "**Monitoring will catch it.**" Only if you know what to look
  for and the alert exists.

## Post-migration artifacts

When done:

- [ ] All characterization tests either deleted (with
      corresponding behavior retired) or adopted as the new
      regression suite.
- [ ] All feature flags removed.
- [ ] All parallel code paths removed.
- [ ] Dashboards + alerts removed for the old path.
- [ ] ADR written: what, why, how it went, what would we do
      differently.
