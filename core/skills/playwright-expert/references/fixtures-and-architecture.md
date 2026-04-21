# Fixtures and test architecture

## Playwright's fixture model

Every test receives a set of fixtures. Core built-in ones:

- `page` — a fresh `Page` with a fresh `BrowserContext`.
- `context` — the `BrowserContext`.
- `browser` — the shared browser instance (reused across tests in
  the worker).
- `request` — a bare API request context.
- `browserName`, `testInfo` — metadata.

Fixtures are dependency-injected. No `beforeEach` needed for
anything that can be a fixture.

## Custom fixtures

```typescript
// tests/fixtures.ts
import { test as base, expect } from "@playwright/test";
import { createUser, deleteUser, User } from "./helpers/users";

type Fixtures = {
  seededUser: User;
};

export const test = base.extend<Fixtures>({
  seededUser: async ({}, use) => {
    const user = await createUser();
    await use(user);
    await deleteUser(user.id);
  },
});

export { expect };
```

Import this `test` in every spec file. Setup runs before the test;
teardown after.

## Auth / signed-in state

The classic approach: sign in once per worker, save the browser
storage state, load it into every test's context.

### One-time sign-in

```typescript
// tests/global.setup.ts
import { test as setup } from "@playwright/test";
import path from "path";

setup("authenticate admin", async ({ page }) => {
  await page.goto("/signin");
  await page.getByLabel("Email").fill(process.env.E2E_ADMIN_EMAIL!);
  await page.getByLabel("Password").fill(process.env.E2E_ADMIN_PASSWORD!);
  await page.getByRole("button", { name: "Sign in" }).click();
  await page.waitForURL("/dashboard");
  await page.context().storageState({ path: "auth/admin.json" });
});
```

### Load in config

```typescript
// playwright.config.ts
export default defineConfig({
  projects: [
    { name: "setup", testMatch: /global\.setup\.ts/ },
    {
      name: "chromium-admin",
      use: { ...devices["Desktop Chrome"], storageState: "auth/admin.json" },
      dependencies: ["setup"],
    },
  ],
});
```

## Per-test data isolation

Shared auth + per-test data:

```typescript
export const test = base.extend<{ account: Account }>({
  account: async ({ page }, use) => {
    const acc = await api.createAccount();
    await page.context().addCookies([{ name: "session", value: acc.token, domain: "localhost", path: "/" }]);
    await use(acc);
    await api.deleteAccount(acc.id);
  },
});
```

Every test gets its own account, signed in via session cookie.

## Projects

Projects are configurations; each project runs the matching tests.

```typescript
export default defineConfig({
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "firefox", use: { ...devices["Desktop Firefox"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } },
    { name: "mobile-chrome", use: { ...devices["Pixel 5"] } },
    { name: "dark-mode", use: { ...devices["Desktop Chrome"], colorScheme: "dark" } },
  ],
});
```

CLI:

```bash
npx playwright test --project=chromium
npx playwright test --project=webkit smoke
```

## Sharding the same tests across projects

```typescript
{
  name: "mobile-safari",
  use: { ...devices["iPhone 13"] },
  testMatch: /critical-path\.spec\.ts/,
}
```

Only critical-path tests run on mobile Safari; full suite runs on
Chromium.

## Page Object Model — use sparingly

Traditional POM:

```typescript
class SigninPage {
  constructor(private page: Page) {}
  async signin(email: string, pw: string) {
    await this.page.getByLabel("Email").fill(email);
    await this.page.getByLabel("Password").fill(pw);
    await this.page.getByRole("button", { name: "Sign in" }).click();
  }
}
```

Pros: reuse, abstraction.
Cons: one more layer; hides what the test is actually doing; changes
cascade.

Modern Playwright practice: **use locators directly in the test**,
extract helpers only when they're repeated 3+ times.

When POM pays off:

- Complex multi-step flows used in many tests (checkout).
- Login-style flows at the top of many suites.
- Pages with 20+ interactive elements and shared semantics.

Otherwise, inline locators keep tests readable.

## Helper functions, not classes

```typescript
// tests/helpers/todo.ts
export async function addTodo(page: Page, text: string) {
  await page.getByRole("textbox", { name: "New todo" }).fill(text);
  await page.keyboard.press("Enter");
  await expect(page.getByRole("listitem").filter({ hasText: text })).toBeVisible();
}
```

Used:

```typescript
await addTodo(page, "buy milk");
```

Simple, composable, no ceremony.

## API-level seeding

**Don't seed through the UI.** It's slow, flaky, and exercises the
wrong thing.

Instead, call the backend API directly:

```typescript
export const test = base.extend<{ seededTodos: Todo[] }>({
  seededTodos: async ({ request, account }, use) => {
    const todos = await Promise.all([
      request.post("/api/todos", { data: { text: "one" } }),
      request.post("/api/todos", { data: { text: "two" } }),
    ]);
    const data = await Promise.all(todos.map((r) => r.json()));
    await use(data);
  },
});
```

Then the test only exercises the UI of the workflow under scrutiny.

## Base URLs and environments

```typescript
// playwright.config.ts
export default defineConfig({
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:3000",
  },
});
```

Tests use relative URLs: `page.goto("/dashboard")`. Environment
flips via env var.

## Web server management

```typescript
webServer: {
  command: "npm run dev",
  url: "http://localhost:3000",
  reuseExistingServer: !process.env.CI,
  timeout: 120_000,
},
```

Starts your app before tests, waits for it, tears it down after.

## Test hygiene

- **One describe block per feature**; don't nest deeply.
- **Test names describe user intent**: `"user cannot delete someone
  else's comment"` — not `"delete button hidden"`.
- **No `beforeAll` for mutable setup.** Use fixtures; `beforeAll` is
  for truly read-only shared data.
- **`test.skip` / `test.fixme`** with a reason.
- **Avoid conditional branches in tests** — if the path diverges,
  it's two tests.
- **Tag tests** (`test.describe.configure({ mode: "serial" })`,
  `test.slow()`) only when needed.

## Cross-test parallelism

`fullyParallel: true` (default) — each test runs in its own worker.
Implies each test needs its own data.

Occasionally you need serialization: legacy sequential flow.

```typescript
test.describe.configure({ mode: "serial" });
test.describe("admin onboarding", () => { ... });
```

Use rarely.

## Fixture scoping

Two scopes: `test` (default, per test) and `worker` (once per worker).

```typescript
apiClient: [async ({}, use) => {
  const client = await ApiClient.create();
  await use(client);
  await client.close();
}, { scope: "worker" }],
```

Use worker scope for:

- Expensive-to-create objects that are read-only.
- Stable API clients shared across tests.

Don't worker-scope anything **mutable** — leaks between tests.
