---
name: playwright-expert
description: End-to-end browser testing with Playwright — locator strategy (accessible roles, not CSS), auto-waiting, fixtures and projects, trace viewer, network interception, visual regression, CI sharding, and the anti-flaky playbook. Complements `core/skills/test-master` (strategy) and `core/rules/accessibility.md`.
source: core
triggers: /playwright, e2e, end-to-end testing, browser automation, playwright test, locator, getByRole, page.evaluate, trace viewer, fixture, video recording, visual regression, Percy, Chromatic, webkit, firefox, headless browser, BrowserContext
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/playwright-expert
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# playwright-expert

Deep Playwright expertise for writing, debugging, and scaling
end-to-end browser tests. Activates when the question is about
browser tests, locator strategy, auto-wait mechanics, fixtures,
trace debugging, network interception, or CI architecture for e2e.

> **See also:**
>
> - `core/skills/test-master/` — testing strategy and what belongs in
>   e2e vs. integration
> - `core/rules/accessibility.md` — role selectors mean your app must
>   have proper semantics
> - `stacks/react/skills/react-expert/` — Testing Library complement
>   for component tests

## When to use this skill

- Designing the e2e suite for a new web app.
- An existing Playwright suite is slow / flaky / hard to maintain.
- Choosing between Playwright and alternatives (Cypress, Selenium).
- Wiring auth, data seeding, and cleanup for e2e.
- Parallelizing / sharding e2e runs in CI.
- Adding visual regression coverage.
- Debugging a Playwright failure from CI traces.

## References (load on demand)

- [`references/locators-and-waiting.md`](references/locators-and-waiting.md)
  — locator strategy (role > test-id > text > CSS), auto-waiting
  semantics, `expect.poll`, network idle, how to *never* use
  `waitForTimeout`.
- [`references/fixtures-and-architecture.md`](references/fixtures-and-architecture.md)
  — custom fixtures, projects for cross-browser / viewport, auth
  storage, per-worker setup, page object model vs. component-scoped
  locators.
- [`references/debugging-and-ci.md`](references/debugging-and-ci.md)
  — trace viewer, UI mode, `--debug`, screenshots/videos, sharding
  in CI, retry policy, quarantine, report artifacts.

## When e2e is the right level — and when it isn't

Use Playwright for:

- **Critical user journeys** — sign up, log in, search → purchase.
- **Cross-browser / cross-viewport** regression (Webkit, Firefox,
  mobile Chromium).
- **True integration** of frontend + backend + external services
  that resists integration-test coverage.
- **Visual regression** on key pages.

Don't use Playwright for:

- **Unit testing React/Vue/Angular components** — use Testing
  Library.
- **Business rule coverage** that could be a unit test.
- **Load testing** — use k6, Gatling, Locust.
- **Every form and button.** Cover paths, not permutations.

## Core workflow

1. **Locator first.** Decide how to find the element *before*
   writing any steps. Prefer `getByRole`, `getByLabel`, `getByText`,
   `getByTestId` — in that order.
2. **Let Playwright wait.** Use `expect()` assertions and built-in
   auto-waiting. Never `waitForTimeout`.
3. **One journey, one test.** No "login + create + delete + report"
   mega-tests. Each test seeded and cleaned independently.
4. **Parallel-safe fixtures.** Shared state is the main source of
   flakes — don't have any.
5. **When it fails in CI, open the trace.** Don't debug from a log
   line.

## Defaults

| Question | Default |
|---|---|
| Runner | `@playwright/test` (built-in) |
| Language | TypeScript |
| Config | One `playwright.config.ts` with projects for browsers |
| Browsers | Chromium always; Webkit + Firefox for consumer apps |
| Locator | `getByRole` → `getByLabel` → `getByText` → `getByTestId` → CSS (last resort) |
| Auth | Storage state persisted per worker (`storageState: 'auth.json'`) |
| Data isolation | Per-test seeded account, cleaned in `afterEach` |
| Trace | `on-first-retry` in CI; `retain-on-failure` locally |
| Video / screenshots | `retain-on-failure` |
| Retries | 2 in CI, 0 locally |
| Parallelism | `fullyParallel: true` |
| Sharding | GitHub Actions matrix with `--shard=i/n` |
| Visual regression | `expect(page).toHaveScreenshot()` with per-project baselines |

## Anti-patterns

- **`page.waitForTimeout(N)`** — the #1 flake source. Use `expect()`
  with the built-in wait or `expect.poll`.
- **CSS selectors on presentation classes** — `.MuiButton-root-234`
  breaks on every library upgrade.
- **Shared auth storage across tests that mutate state** — they
  corrupt each other.
- **`beforeAll` for DB seeding** — creates cross-test coupling.
  Per-test seeding is parallelizable and deterministic.
- **Assertions without Playwright's `expect`** — losing auto-wait
  and producing flakes.
- **Clicking by text in internationalized apps** — text changes per
  locale. Use role + aria-label.
- **Over-mocking the network** — you bypass the very thing e2e is
  supposed to test. Mock only truly external flaky services.
- **One giant test file** — split by journey; easier to run one
  file.
- **Headless-only test development** — you miss visual issues. Use
  `--headed` locally during authoring.

## Output format

For a test design:

```
Journey:          <short name>
Preconditions:    <seeded data>
Steps:
  1. <goto, action, assert>
  2. ...
Postconditions:   <cleanup>
Fixtures used:    <auth, db, api>
Cross-browser:    chromium | webkit | firefox
```

For a flake investigation:

```
Test:             <file::test name>
Symptom:          <what fails>
Trace insight:    <what the trace shows>
Cause (one of):
  - timing / auto-wait issue
  - locator selecting wrong element
  - shared state
  - external flakiness
Fix:              <concrete change>
Prevention:       <general rule to codify>
```

## Playwright vs. alternatives

- **Cypress** — excellent DX, but single-origin limitation (until
  recently), no native parallelism without paid service, Chromium-
  focused. Fine for early-stage apps; hits walls at scale.
- **Selenium / WebdriverIO** — mature, every language, but auto-wait
  is bolt-on, locator ergonomics are weaker. Use if you need a very
  broad browser matrix.
- **Puppeteer** — automation, not test runner. Don't author tests
  in it; use Playwright.
- **Cross-browser native testing (BrowserStack / SauceLabs)** — run
  Playwright against their grid for edge cases (old Safari, mobile
  Safari real).
