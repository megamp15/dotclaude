# Debugging and CI

## The three debugging surfaces

1. **UI Mode** (`--ui`) — live time-travel inspector. Best for
   authoring and debugging locally.
2. **Trace Viewer** — post-mortem review of a failed run. Main tool
   for CI failures.
3. **Codegen** — record interactions to generate locator suggestions.

## UI Mode

```bash
npx playwright test --ui
```

Features:

- Run tests / watch files.
- DOM snapshot per step; click into any step to see state.
- Network log.
- Console log.
- Video playback.

Use this to author locators: the DOM inspector shows which role/
name variants would match.

## Trace Viewer

Enable traces in config:

```typescript
use: {
  trace: process.env.CI ? "on-first-retry" : "retain-on-failure",
},
```

On failure, Playwright writes `trace.zip`. Open:

```bash
npx playwright show-trace trace.zip
```

Trace contains:

- DOM snapshots before + after every action (time travel).
- Network requests (request / response bodies when captured).
- Console messages.
- Action timeline with wall-clock.
- Source map back to your test code.

**Rule:** when a test fails in CI, first open the trace. Don't
speculate from the log.

### Trace modes

| Mode | Behavior | Cost |
|---|---|---|
| `off` | No trace | 0 |
| `on` | Trace every test | High |
| `retain-on-failure` | Discard trace for passing tests, keep for failures | Low |
| `on-first-retry` | Only trace on retried tests | Very low |

CI default: `on-first-retry`. Local default: `retain-on-failure`.

## Screenshots and video

```typescript
use: {
  screenshot: "only-on-failure",
  video: "retain-on-failure",
},
```

Available in `test-results/` per test after a run.

## `page.pause()`

Inside a test:

```typescript
await page.pause();
```

Launches the inspector; test is paused. Useful for debugging
specific steps.

## `DEBUG` env var

```bash
DEBUG=pw:api npx playwright test
```

Verbose log of API calls made to the browser. Overkill in most
cases; occasionally useful when the test isn't producing the
expected action.

## `--debug` flag

```bash
npx playwright test --debug
```

Opens the inspector pre-paused at the first action. Step through.

## Headed mode locally

```bash
npx playwright test --headed
```

Runs with the browser visible. Use when:

- Writing locators against a running app.
- Debugging animations / transitions.
- Watching an actual page render to see if visual state matches.

Default to headless to match CI behavior.

## The "only in CI" flake

Step 1: reproduce locally.

```bash
CI=1 npx playwright test --repeat-each 20
```

If it fails 2/20, you have a flake. Investigate with trace.

Step 2: if still can't reproduce, enable CI traces for *all* tests
temporarily and inspect the failing one.

Step 3: common culprits:

- Timing — CI runner is slower; `timeout` too tight.
- Viewport / font differences — use `ignoreFontsNotLoaded`.
- External services — cache / replay or mock.
- DB state bleed — add isolation.

## Running one test

```bash
npx playwright test tests/auth/signin.spec.ts
npx playwright test -g "can sign in"
npx playwright test tests/auth -g "sign"
```

`.only` and `.skip` modifiers:

```typescript
test.only("focus on this one", ...);
test.skip("not ready", ...);
```

Delete `.only` before committing (lint rule enforces this).

## CI — minimum viable

```yaml
# .github/workflows/e2e.yml
name: e2e
on: [pull_request, push]
jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npx playwright install --with-deps
      - run: npx playwright test
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 7
```

## Sharding

Tests split across N runners:

```yaml
strategy:
  fail-fast: false
  matrix:
    shard: [1/4, 2/4, 3/4, 4/4]
steps:
  - run: npx playwright test --shard=${{ matrix.shard }}
```

Each runner executes its slice. Linear speedup.

Combine with the merge-reports step:

```yaml
- uses: actions/upload-artifact@v4
  with:
    name: blob-report-${{ matrix.shard }}
    path: blob-report
    retention-days: 1

# In a separate job:
- run: npx playwright merge-reports --reporter=html ./all-blob-reports
```

## Reporter configuration

```typescript
reporter: [
  ["html", { outputFolder: "playwright-report", open: "never" }],
  ["blob", { outputDir: "blob-report" }],
  ["github"],
  ["json", { outputFile: "results.json" }],
],
```

- `html` — drillable per-test inspector, local review.
- `blob` — shard-friendly intermediate; merge into one report.
- `github` — PR annotations.
- `json` — programmatic post-processing.

## Retry policy

```typescript
retries: process.env.CI ? 2 : 0,
```

Why 2: catches transient network flakes; third attempt usually
indicates a real bug. Retries should be **additive to trace
investigation**, not a flake-masking strategy.

## Flaky-test quarantine

Mark known-flaky tests and run them in a separate, non-blocking job:

```typescript
test.fixme("flaky: payment webhook timing", async () => { ... });

// Or with a tag
test("payment flow @flaky", async () => { ... });

// Run only @flaky in their own job:
// npx playwright test -g "@flaky"
```

Quarantine with a TTL (e.g., "fix within 2 weeks or delete").

## Visual regression

```typescript
await expect(page).toHaveScreenshot("dashboard.png", {
  maxDiffPixelRatio: 0.001,
});
```

First run records the baseline. Subsequent runs compare.

Tips:

- **Mask dynamic regions** (timestamps, avatars): `mask: [page.getByTestId("live-feed")]`.
- **Per-project baselines** — fonts render differently on Chromium
  vs. Webkit.
- **Fix timezone / locale in config** to avoid text-layout drift.
- **Hosted services** — Percy, Chromatic, Argos CI — offer better
  diff UX and cross-browser baselines.

## Accessibility checks

Integrate `@axe-core/playwright`:

```typescript
import AxeBuilder from "@axe-core/playwright";

test("no a11y violations", async ({ page }) => {
  await page.goto("/");
  const results = await new AxeBuilder({ page }).analyze();
  expect(results.violations).toEqual([]);
});
```

Budget violations early: if the baseline isn't clean, pin the
current set and don't let it grow.

## Performance assertions (experimental)

Playwright can collect web vitals:

```typescript
const metrics = await page.evaluate(() =>
  JSON.stringify(performance.getEntriesByType("navigation"))
);
```

Or use Lighthouse integration via `playwright-lighthouse`. Expect
flaky results on shared CI — use a dedicated perf environment for
stable numbers.

## Useful CLI flags

```bash
--headed                    # show browser
--debug                     # inspector
--ui                        # UI mode
-g <pattern>                # grep test names
--project=<name>            # run only this project
--repeat-each=<n>           # run each test N times (flake hunt)
--fail-fast                 # stop on first failure
--list                      # list tests without running
--workers=<n>               # parallel workers
--trace=on                  # force trace
--update-snapshots          # rewrite visual baselines
```

## Post-run artifacts to preserve

In CI always save:

- `playwright-report/` — full HTML report.
- `test-results/` — per-test artifacts (trace, video, screenshots).
- `blob-report/` — if sharding.

Upload as workflow artifacts with 7-day retention (or longer for
release branches).
