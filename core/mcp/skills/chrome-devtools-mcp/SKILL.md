---
name: chrome-devtools-mcp
description: Drive a real Chrome browser for frontend testing, debugging, and performance profiling. Heavy context footprint — use only for active browser work.
source: core/mcp
triggers: open in browser, test in browser, browser automation, inspect page, screenshot, performance trace, lighthouse
---

# chrome-devtools-mcp

Drive an actual Chrome instance for tasks that need real browser behavior:
DOM inspection, network traces, CPU profiling, screenshots, interactive
testing. Only useful when a browser is genuinely required.

## Weight warning

Loading this MCP costs ~17k tokens of context (26 tools) every session.
Prefer scoping to a specific session rather than always-on:

```
claude --mcp-config .claude/mcp/chrome-devtools.json
```

Or add it to `.mcp.json` only when frontend/webapp work is the current focus.

## When to use

- Reproducing a frontend bug that needs a real DOM/network trace.
- Interactive UI testing ("click the button, then check that X appears").
- Visual verification via screenshot.
- Performance profiling — CPU traces, rendering performance, network waterfall.
- Checking console errors and network failures on a real page.
- Scraping or automating sign-in flows on pages that require JS execution (unlike `fetch`).

## When NOT to use

- Static doc fetching — `fetch` MCP is lighter.
- Backend-only testing — use the project's test runner.
- Anything in CI — use Playwright or Puppeteer directly, not this MCP.
- Simple curl-like requests.

## Core tool categories

- **Navigation:** `navigate_page`, `new_page`, `close_page`, `list_pages`, `select_page`.
- **Inspection:** `take_snapshot` (AX tree), `take_screenshot`, `evaluate_script`, `list_console_messages`.
- **Interaction:** `click`, `drag`, `fill`, `fill_form`, `hover`, `upload_file`.
- **Network:** `list_network_requests`, `get_network_request`.
- **Performance:** `performance_start_trace`, `performance_stop_trace`, `performance_analyze_insight`.
- **Dialogs & waiting:** `handle_dialog`, `wait_for`.
- **Emulation:** `emulate_cpu`, `emulate_network`, `resize_page`.

## Workflow patterns

### Reproduce a frontend bug

1. `new_page` to the affected URL.
2. `take_snapshot` to capture structure.
3. `list_console_messages` and `list_network_requests` to capture errors.
4. `click` / `fill` to reproduce.
5. Repeat snapshot after each interaction to track state changes.

### Performance check

1. `new_page` to target URL.
2. `performance_start_trace`.
3. Perform the scenario (navigation, user action).
4. `performance_stop_trace`.
5. `performance_analyze_insight` for key findings.

### Visual verification

1. `new_page`.
2. `resize_page` if testing a specific viewport.
3. `take_screenshot`, compare to expected.

## Pitfalls

- **Snapshot before click.** Element refs change between snapshots. Always re-snapshot before interacting if the page may have changed.
- **Async state.** Use `wait_for` on a selector or condition before asserting. Don't hardcode sleeps.
- **Iframe content** is usually not accessible — only the top frame.
- **Session persistence.** Cookies and localStorage persist across the session; clear intentionally if isolation matters.
- **Leaving pages open.** Close pages you're done with — they consume browser resources and context.

## Safety

- Never enter credentials through this MCP into real accounts.
- Never automate destructive actions on live systems (deletes, sends, payments) without explicit user confirmation for each one.
