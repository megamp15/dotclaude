---
source: stacks/htmx-alpine
---

# Stack: HTMX + Alpine.js

Server-driven hypermedia frontend with small client-side enhancements.
Layers on top of `core/`. Works with any backend (Django, FastAPI,
Starlette, Flask, Go, Rails, .NET, etc.) — the backend returns HTML
fragments; HTMX swaps them; Alpine handles the little bits of client
state.

## The mental model

- **Backend renders HTML.** Whole pages, or fragments for partial
  updates. The server is authoritative for state.
- **HTMX = smart links and forms.** `hx-get`, `hx-post`, `hx-target`,
  `hx-swap`, `hx-trigger` — declarative AJAX as HTML attributes.
- **Alpine = local UI state.** Toggles, dropdowns, tab highlights,
  optimistic affordances. Anything ephemeral that doesn't need the
  server.

If you find yourself building a state machine in Alpine: it probably
belongs on the server. If you find yourself round-tripping the server
for a toggle: it probably belongs in Alpine.

## When HTMX+Alpine is the right choice

- CRUD apps with modest client interactivity.
- Admin panels, internal tools, dashboards.
- Content-heavy sites where server rendering wins for SEO + performance.
- Progressive enhancement over server-rendered pages.

When it's the wrong choice:

- Heavy client-side state (collaborative editors, infinite-canvas apps).
- Offline-first.
- Mobile-app-like UX with complex gestures and transitions.

For those: React/Angular/Svelte. Don't force HTMX up that hill.

## HTMX conventions

### Attributes that earn their keep

| Attribute | Use |
|---|---|
| `hx-get` / `hx-post` / `hx-put` / `hx-delete` | Trigger a request on interaction |
| `hx-target="#id"` or `closest .card` | Where to inject the response |
| `hx-swap="innerHTML"` / `outerHTML` / `beforeend` / `afterend` | How to inject |
| `hx-trigger="change delay:300ms"` | When to fire (with debounce, throttle, keyup[key=='Enter'], etc.) |
| `hx-push-url="true"` | Update browser URL after swap |
| `hx-vals='{"extra": "data"}'` | Extra parameters with the request |
| `hx-indicator="#spinner"` | Show/hide during request |
| `hx-confirm="Delete?"` | Native confirm prompt |
| `hx-boost="true"` | Make normal links/forms behave like HTMX (progressive enhancement) |

### Swap strategy

- **Partial update**: `hx-target="#item-42" hx-swap="outerHTML"` — server returns the new `<div id="item-42">`.
- **Append**: `hx-target="#list" hx-swap="beforeend"` — server returns just the new item.
- **Inline replace**: `hx-swap="innerHTML"` — default; replaces target's contents.
- **Out-of-band** updates: `hx-swap-oob="true"` on a root element in the response; lets a single response update multiple places on the page.

Keep swaps small. The whole point is not shipping bundles; don't waste that by re-rendering the whole page on every click.

### Request/response contract

- **Server returns HTML fragments**, not JSON. `HX-Request` header tells you the request came from HTMX — use it to return the fragment instead of a full page.
- **`HX-Trigger` response header** fires custom events on the client (good for toasts, "refresh the counter", etc.).
- **`HX-Redirect` header** does client-side navigation after a submit (use for login/logout).
- **`HX-Push-Url` response header** updates the URL bar even if `hx-push-url` wasn't on the request.

### Security

- **CSRF tokens on every mutating request.** HTMX sends whatever your form has; make sure your framework's CSRF middleware still runs.
- **Sanitize anything echoed back**, same as for any server-rendered HTML — XSS risk is unchanged.
- **`hx-disable`** at a root element disables HTMX processing for a subtree — useful around user-submitted content.

## Alpine conventions

### Scope

`x-data` creates a scope. Each `x-data` element has its own reactive state. Nest `x-data` to create inner scopes.

```html
<div x-data="{ open: false }">
  <button @click="open = !open">Toggle</button>
  <div x-show="open" x-transition>
    ...
  </div>
</div>
```

Use Alpine for:

- Disclosure: dropdowns, accordions, mobile menus.
- Toggle + transition state: modals, tabs.
- Input affordances: password visibility toggle, character counter.
- Client-validated form errors before submit.
- Optimistic UI: disable the button immediately, show a spinner.

Don't use Alpine for:

- Global app state (URL / server is the source of truth).
- Anything that survives a page reload (that's server state or `localStorage`).
- Complex async flows (HTMX handles that).

### Directives worth knowing

| Directive | Use |
|---|---|
| `x-data` | Declare reactive state for this scope |
| `x-show` / `x-if` | Conditional visibility (`x-show` keeps in DOM; `x-if` removes) |
| `x-bind:class` / `:class` | Dynamic attributes |
| `x-on:click` / `@click` | Event handlers |
| `x-model` | Two-way binding on inputs |
| `x-text` / `x-html` | Set content |
| `x-for` | Loop |
| `x-transition` | Basic enter/leave transitions |
| `x-cloak` | Hide until Alpine initialized (pair with CSS `[x-cloak] { display: none }`) |
| `x-ref` / `$refs` | Get reference to an element |
| `$dispatch('event-name', data)` | Dispatch a DOM event (HTMX can listen via `hx-trigger`) |

### `$dispatch` + `hx-trigger` — the bridge

Alpine can trigger HTMX requests via events:

```html
<div x-data @save="htmx.trigger($el, 'custom-save')">
  <input x-model="q" @input.debounce.300ms="$dispatch('save')" />
  <div hx-post="/search" hx-trigger="custom-save" hx-target="#results"></div>
</div>
```

Or simpler, with `hx-trigger` listening to custom events directly:

```html
<div hx-post="/search" hx-trigger="my-event from:body" hx-target="#results"></div>
<!-- elsewhere -->
<button x-data @click="$dispatch('my-event', { q: 'foo' })">Search</button>
```

## Styling

- **Tailwind** pairs exceptionally well with HTMX+Alpine. No framework components to style around; utility classes directly on elements.
- **CSS scoping**: with server-rendered HTML there's no built-in scoping. If you need isolation, BEM or a utility-first framework is your only real option.

## Testing

- **Backend tests**: standard — request returns expected HTML, right status, right headers (`HX-Trigger`, etc.).
- **E2E**: Playwright or Cypress. HTMX apps are very testable end-to-end because state is server-authoritative — no "wait for react to hydrate."
- **Snapshot testing** for fragment responses is worthwhile; HTMX returns are small and stable.

## Performance

- **Out-of-band swaps** let you update a counter + the list + a toast from one response.
- **`hx-boost="true"`** on a root `<body>` makes all regular `<a>` and `<form>` act like HTMX — SPA feel with fallback when JS is off.
- **Debounce inputs** (`hx-trigger="keyup changed delay:300ms"`) — don't hammer the server on every keystroke.
- **Indicator strategy**: `hx-indicator` is nice but don't block the user — keep the existing UI interactive where possible.

## Do not

- Do not build client-side state machines in Alpine. That's a signal you need a real SPA or you need to move state to the server.
- Do not return JSON from HTMX endpoints (unless it's specifically a non-HTMX AJAX path). HTMX wants HTML.
- Do not reach for Alpine when HTMX can handle it, or vice versa. Each has a specific purpose.
- Do not skip CSRF protection because "it's just HTMX."
- Do not use `hx-swap="outerHTML"` on the target itself and then expect the target's HTMX attributes to persist — they're replaced too. If you need them, re-include in the response.
- Do not mix HTMX responses with full-page reloads randomly. Consistency matters for perceived polish.
