# Locators and waiting

## Locator priority

Playwright's locator API is your test's contract with the UI. Lower
is better:

1. **`getByRole`** — matches the accessible role + name. Best for
   real UI elements.
2. **`getByLabel`** — form fields via their label.
3. **`getByPlaceholder`** — form fields by placeholder text.
4. **`getByText`** — non-interactive text (prefer role + name for
   buttons/links).
5. **`getByTestId`** — explicit test anchor (`data-testid`).
6. **CSS / XPath** — last resort; brittle.

### Why role-first

```typescript
await page.getByRole("button", { name: "Sign in" }).click();
```

- **Survives redesign.** Class names change, ARIA roles don't.
- **Forces accessibility.** If your button has no name, screen
  readers can't use it either.
- **Internationalization-aware.** `name` can be a regex:
  `{ name: /sign.?in/i }`.

### Role-name patterns

```typescript
page.getByRole("button", { name: "Submit" });
page.getByRole("link", { name: "Home" });
page.getByRole("heading", { name: /dashboard/i, level: 1 });
page.getByRole("textbox", { name: "Email" });
page.getByRole("combobox", { name: "Country" });
page.getByRole("checkbox", { name: "Remember me" });
page.getByRole("dialog", { name: "Confirm delete" });
```

### Scoping locators

Start at the container, narrow in:

```typescript
const dialog = page.getByRole("dialog", { name: "Confirm delete" });
await dialog.getByRole("button", { name: "Delete" }).click();
```

This avoids matching the same button on a page that shows both the
dialog and a background version.

### When `data-testid` is right

- Non-semantic elements you need to interact with (a `<div>` as a
  custom slider thumb).
- Dynamic content with no stable text (revenue charts).
- Widgets whose ARIA is ambiguous (`getByRole("generic")` matching
  many).

Rule: **add `data-testid` last**, after confirming no role-based
locator works.

Keep `data-testid` stable: `data-testid="user-card-avatar"` — not
`data-testid="c-UXJ92"`.

### CSS / XPath — why not

```typescript
// Brittle
page.locator(".MuiButton-root-234.sc-fzowVh");
// Also brittle
page.locator("//div[@class='header']//button[2]");
```

Any change to the DOM structure or CSS-in-JS hash breaks the test.
Use CSS only for:

- Component-library selectors that are documented stable
  (`.mantine-Button-root`).
- Nth-child navigation that truly reflects semantics.

## Chaining and filtering

```typescript
page
  .getByRole("row")
  .filter({ hasText: "john@example.com" })
  .getByRole("button", { name: "Edit" });
```

`filter()` is composable. Use `has:` and `hasText:` to scope.

## Handling lists

```typescript
const rows = page.getByRole("row");
await expect(rows).toHaveCount(5);
await rows.nth(0).getByRole("cell", { name: /id 1/ }).click();
```

`nth()` is 0-indexed.

## Auto-waiting semantics

Playwright's `expect()` (and actions like `click`, `fill`, `press`)
**auto-wait** for actionability:

- Element visible
- Stable (no animation / transform changes)
- Receiving events (not covered by another element)
- Enabled

Default timeout: 5 s per action, 5 s per assertion. Configure:

```typescript
// playwright.config.ts
export default defineConfig({
  expect: { timeout: 10_000 },
  use: { actionTimeout: 10_000, navigationTimeout: 15_000 },
});
```

Per-assertion override:

```typescript
await expect(toast).toBeVisible({ timeout: 15_000 });
```

## Assertions that auto-wait

```typescript
await expect(locator).toBeVisible();
await expect(locator).toBeHidden();
await expect(locator).toBeEnabled();
await expect(locator).toBeDisabled();
await expect(locator).toHaveText("Hello");
await expect(locator).toContainText(/welcome/i);
await expect(locator).toHaveValue("john@x.com");
await expect(locator).toHaveAttribute("href", /\/dashboard/);
await expect(locator).toHaveClass(/active/);
await expect(locator).toHaveCount(3);

await expect(page).toHaveURL(/\/settings$/);
await expect(page).toHaveTitle(/Settings/);
```

All wait up to the configured timeout before failing.

## `expect.poll` — custom polling

When the assertion isn't on a locator (API call, computed value):

```typescript
await expect
  .poll(async () => (await api.getUser("u1")).status, { timeout: 10_000, intervals: [200, 500, 1000] })
  .toBe("active");
```

Polls the function until the assertion passes or the timeout
elapses.

## `waitForFunction` — in-page predicate

```typescript
await page.waitForFunction(
  () => window.hydrated === true,
  null,
  { timeout: 5_000 },
);
```

Use for app-level flags ("React hydration done", "analytics script
loaded").

## Navigation

```typescript
await page.goto("/dashboard");
await page.getByRole("link", { name: "Settings" }).click();
await expect(page).toHaveURL(/\/settings$/);
```

Playwright auto-waits for the `load` event on `goto`. For SPA
navigation, **assert on the next state** — don't wait for network
idle.

For explicit navigation wait:

```typescript
await Promise.all([
  page.waitForURL("/dashboard"),
  page.getByRole("button", { name: "Continue" }).click(),
]);
```

## Network interception

Mock an external API:

```typescript
await page.route("**/api.stripe.com/**", async (route) => {
  await route.fulfill({
    status: 200,
    contentType: "application/json",
    body: JSON.stringify({ id: "ch_fake", status: "succeeded" }),
  });
});
```

Intercept to observe:

```typescript
const requests: string[] = [];
page.on("request", (req) => requests.push(req.url()));
```

**Only mock external APIs.** Mocking your own backend defeats the
purpose of e2e.

## Anti-pattern: `waitForTimeout`

```typescript
// Never
await page.waitForTimeout(2000);
await expect(toast).toBeVisible();
```

Replace with:

```typescript
await expect(toast).toBeVisible({ timeout: 5000 });
```

If you truly need to pause (e.g., animating sprite between frames),
wait for the DOM signal instead:

```typescript
await expect(sprite).toHaveClass(/animation-complete/);
```

## Handling flaky third-party scripts

Block them outright:

```typescript
await page.route(/analytics\.com|googletagmanager/, (r) => r.abort());
```

Third-party scripts are a top flake source. Block at the page level
unless the test is specifically about them.

## File uploads and downloads

```typescript
await page
  .getByLabel("Profile picture")
  .setInputFiles("tests/fixtures/avatar.png");

const [download] = await Promise.all([
  page.waitForEvent("download"),
  page.getByRole("link", { name: "Export CSV" }).click(),
]);
await download.saveAs("/tmp/out.csv");
```

## Keyboard and mouse

```typescript
await page.keyboard.press("Tab");
await page.keyboard.press("Enter");
await page.keyboard.type("hello");

await locator.hover();
await locator.dragTo(target);
```

Prefer semantic actions (`.click()`, `.fill()`) when available.

## iFrames

```typescript
const frame = page.frameLocator("iframe[title='Payments']");
await frame.getByLabel("Card number").fill("4242 4242 4242 4242");
```

Scoped locators work inside the frame.

## Browser contexts and tabs

```typescript
const newPagePromise = context.waitForEvent("page");
await page.getByRole("link", { name: "Open docs" }).click();
const newPage = await newPagePromise;
await expect(newPage).toHaveTitle(/Docs/);
```

## Debugging locators

- **VS Code / JetBrains** extension — hover over locator → inspect
  live element.
- **Codegen** — `npx playwright codegen URL` generates locator
  suggestions from your clicks.
- **UI Mode** — `npx playwright test --ui` steps through with time-
  travel inspector.
- **`page.pause()`** — pauses inside a running test; inspector opens.
