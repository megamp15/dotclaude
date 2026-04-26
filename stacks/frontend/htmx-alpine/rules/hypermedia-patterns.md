---
source: stacks/htmx-alpine
name: hypermedia-patterns
description: Patterns for well-designed HTMX+Alpine apps — fragment endpoints, out-of-band swaps, event choreography, and the server/client state split. Load when designing HTMX routes or reviewing HTMX+Alpine code.
triggers: htmx, hx-get, hx-post, hx-swap, hx-target, hx-trigger, alpine, x-data, hypermedia, fragment, oob swap
globs: ["**/*.html", "**/*.jinja", "**/*.jinja2", "**/*.j2", "**/templates/**/*.html"]
---

# Hypermedia patterns (HTMX + Alpine)

Disciplines that keep server-rendered apps maintainable.

## The state split

Ask, for each piece of UI state: **"Does losing this matter on reload?"**

- **Yes** (selected filter, form draft, pagination position) → server, reflected in URL or session.
- **No** (modal open, tooltip hover, password show/hide) → Alpine.

URL as state is underrated. `?filter=active&page=3` means the user can
bookmark, share, or reload without losing context. HTMX `hx-push-url`
makes this cheap.

## Fragment endpoints

A URL usually has two job modes:

- **Full page** when hit by a browser navigation.
- **Fragment** when hit by HTMX.

Pattern:

```python
# FastAPI / Starlette pseudocode
@app.get('/items')
def items(request, q: str = ''):
    items = search(q)
    if request.headers.get('HX-Request') == 'true':
        return templates.TemplateResponse('items/_list.html', {'items': items})
    return templates.TemplateResponse('items/index.html', {'items': items})
```

Or with a `_layout.html` base template, `items/index.html` extends the layout and includes `items/_list.html` as a partial — so the partial is the same markup in both paths.

**Naming convention**: partials prefixed with `_` (e.g. `_list.html`, `_row.html`). Makes it obvious in templates dir what's directly routable vs what's a fragment.

## Response shape — return exactly what the swap needs

Bad pattern: endpoint returns a full list wrapped in the page chrome, HTMX swaps just the list; duplicate work, unneeded bytes.

Good pattern: endpoint returns just the list content (`<ul><li>...</li></ul>`), HTMX swaps it into the target. Fragment endpoints return fragments.

## Out-of-band (OOB) swaps for multi-region updates

A single user action often should update multiple regions. Submit a new todo → update the list, update the count in the header, show a toast. One request, three updates:

```html
<!-- Response body -->
<li id="todo-item-42">Buy milk</li>                    <!-- main swap: appended to #list -->

<div id="todo-count" hx-swap-oob="true">5</div>         <!-- OOB: replaces #todo-count -->

<div id="toast-slot" hx-swap-oob="beforeend">           <!-- OOB: appends to toast area -->
  <div class="toast">Saved</div>
</div>
```

Request was `hx-post="/todos" hx-target="#list" hx-swap="beforeend"`. Main swap handles the list; OOB fragments handle the other regions. No second request.

## Event choreography

When one action should trigger another — say, deleting an item and then reloading analytics — use events, not chained calls.

Server emits an event via response header:

```
HX-Trigger: {"todo-deleted": {"id": 42}}
```

Client listens:

```html
<div hx-get="/stats" hx-trigger="todo-deleted from:body" hx-target="#stats-region">
```

This keeps endpoints cohesive (delete endpoint doesn't also return stats) and makes the wiring declarative.

## Forms

- **`hx-post` on the form**, not on the button. Submission on Enter works naturally.
- **Redisplay on validation error** — return 422/400 with the form fragment plus error messages. HTMX will swap it in place.
- **`hx-swap="outerHTML"`** on the form so the rendered-with-errors version fully replaces the original.
- **Disable the submit button during request** via Alpine + `htmx:beforeRequest` / `htmx:afterRequest` events, or `hx-disable` on the form.

```html
<form hx-post="/register" hx-swap="outerHTML" x-data="{ sending: false }"
      @htmx:before-request="sending = true"
      @htmx:after-request="sending = false">
  <input name="email" required />
  <button type="submit" :disabled="sending">
    <span x-show="!sending">Register</span>
    <span x-show="sending">Sending…</span>
  </button>
</form>
```

## Optimistic UI

HTMX is request-then-swap by default (pessimistic). For quick affordances:

- **Client-side**: Alpine disables the button, shows a spinner, local flag flips.
- **Server confirms**: swap in the real row or revert on failure via HTMX error handling (`htmx:responseError`).

Keep this narrow — optimistic behaviors get bug-prone fast.

## Infinite scroll / pagination

```html
<div id="page-1">...</div>
<div id="page-2" hx-get="/items?page=2" hx-trigger="revealed" hx-swap="outerHTML">
  Loading...
</div>
```

The trigger `revealed` fires when the element scrolls into view. The server returns the next page's content plus another "sentinel" div for page 3. Chains until the server omits the sentinel.

Alternative: explicit "Load more" button — simpler, accessible, often preferable.

## `hx-boost` — progressive enhancement

On a layout root:

```html
<body hx-boost="true">
```

All normal `<a href>` and `<form method="post">` become AJAX requests that swap the `<body>` (or whatever target you specify). URL updates automatically. If JS is disabled, everything still works as a classic server-rendered site.

This gets you SPA-feel performance (no full-page reloads) with graceful degradation.

## Accessibility

- **Announce swaps** to screen readers when appropriate. Pattern: `aria-live="polite"` on a region that gets swapped messages.
- **Focus management** after swap: `hx-on::after-swap="document.getElementById('first-input').focus()"` — critical for keyboard users.
- **`hx-disable`** keeps server-supplied HTML from being HTMX-processed; use around user-submitted content.
- **Avoid `hx-swap="outerHTML"` for things containing focus** — focus is lost unless you restore it.

## Error handling

Server returns 4xx/5xx → HTMX doesn't swap by default (treats error as non-swap). To handle:

```html
<body hx-on::response-error="showToast('Something went wrong')">
```

Or server returns 422 with the form fragment and `HX-Retarget: #form` if needed. Good pattern for validation errors.

## Common pitfalls

- **Full-page HTML returned to HTMX request** — page-within-page in the DOM. Always branch on `HX-Request`.
- **HTMX attributes lost after swap** — targeted element replaced wholesale; new element needs the attributes re-included (or use event delegation via `hx-trigger="click from:body target:.thing"`).
- **Alpine state reset on swap** — Alpine reinitializes when the DOM changes. If you need state to survive, store it in a parent `x-data` that doesn't get swapped.
- **CSRF token expired in a long-lived page** — tokens rotate; fetch a fresh token before mutating requests (or use a pattern like HTMX's `hx-headers` fetching from a meta tag).
- **Double-submits** — disable button on `htmx:beforeRequest`, enable on `htmx:afterRequest`.
- **Forgetting `hx-target` on `outerHTML` replacement of a container** — the container HTMX replaces disappears, so subsequent triggers aimed at it fail silently.

## When to stop

If you find yourself:

- Writing lots of Alpine code for a single page.
- Needing complex state coordination between multiple Alpine scopes.
- Implementing optimistic UI in Alpine that has to sync with the server in complicated ways.
- Duplicating state between server-rendered attributes and Alpine refs.

...you may have outgrown HTMX+Alpine for this page. Either move that page to a proper SPA component, or refactor server-side to simplify.
