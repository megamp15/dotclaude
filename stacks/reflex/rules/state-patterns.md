---
source: stacks/reflex
name: reflex-state-patterns
description: Reflex state design — how to split state classes, when to use computed vars, async vs background events, immutable updates, cross-state access. Load when designing or reviewing rx.State classes.
triggers: rx.State, rx.var, rx.event, reflex state, reflex event, reflex background, reflex component, reflex page
globs: ["**/state.py", "**/states/**/*.py", "**/rxconfig.py", "**/*.py"]
---

# Reflex state patterns

The quality of a Reflex app is mostly determined by the quality of its
state design. Get this right; everything else follows.

## Split state by feature, not by type

**Bad:**

```python
class AppState(rx.State):
    users: list[User] = []
    user_filter: str = ''
    dashboard_tabs: list[str] = []
    current_tab: str = ''
    theme: str = 'light'
    orders: list[Order] = []
    selected_order_id: int = 0
    # ... 40 more fields
```

Every page re-subscribes to the whole class. Changes to unrelated fields still notify the component (in the worst case, re-render).

**Good:**

```python
class AppState(rx.State):                 # app-wide, small
    user: User | None = None
    theme: str = 'light'

class UsersPageState(AppState):           # users page only
    users: list[User] = []
    filter: str = ''

    @rx.var
    def filtered_users(self) -> list[User]:
        return [u for u in self.users if self.filter.lower() in u.name.lower()]

class DashboardState(AppState):           # dashboard only
    tabs: list[str] = []
    current_tab: str = ''
```

Subclassing `AppState` gets you the user/theme fields on dashboard pages too. Each page only pays for the state it uses.

## Computed vars over manual recomputation

```python
# BAD — manually recompute in every event handler
class State(rx.State):
    items: list[Item] = []
    total: int = 0

    def add_item(self, item: Item):
        self.items = [*self.items, item]
        self.total = sum(i.price for i in self.items)   # easy to forget

    def remove_item(self, idx: int):
        self.items = [i for j, i in enumerate(self.items) if j != idx]
        self.total = sum(i.price for i in self.items)   # duplicated

# GOOD — derived automatically
class State(rx.State):
    items: list[Item] = []

    @rx.var
    def total(self) -> int:
        return sum(i.price for i in self.items)
```

Computed vars re-evaluate only when their signal-input changes. If you find yourself writing the same derivation in two event handlers, make it a computed var.

## Immutable updates

Reflex detects state changes by comparing field references. In-place mutation may or may not trigger re-render — don't rely on it.

```python
# BAD — may not re-render
self.items.append(new)
self.items[0].name = "updated"
self.settings["theme"] = "dark"

# GOOD — new references, always re-renders
self.items = [*self.items, new]
self.items = [dataclasses.replace(self.items[0], name="updated"), *self.items[1:]]
self.settings = {**self.settings, "theme": "dark"}
```

This is identical to React's state-update discipline. Treat state fields as immutable.

## Async events for I/O; background events for long work

```python
class State(rx.State):
    users: list[User] = []
    loading: bool = False

    async def load_users(self):
        self.loading = True
        yield                                  # flush the loading state to the frontend
        self.users = await self.fetch_users()
        self.loading = False

    async def fetch_users(self) -> list[User]:
        async with httpx.AsyncClient() as client:
            resp = await client.get("/api/users")
            return [User(**u) for u in resp.json()]
```

**`yield`** inside an event handler flushes intermediate state to the client. Without it, the client sees the final state only — the loading flicker you wanted is invisible.

For genuinely long tasks (minutes, not seconds):

```python
@rx.event(background=True)
async def long_job(self):
    async with self:                        # re-acquire lock to write state
        self.status = "starting"
        yield

    await asyncio.sleep(60)                 # heavy work outside lock

    async with self:
        self.status = "done"
        yield
```

Background events run outside the default session lock so they don't block other events. Re-enter the lock (`async with self:`) whenever you touch state.

## Event specs — returning side effects

Event handlers can return (or yield) Reflex event specs to trigger
browser-side behavior:

```python
async def login(self, form_data: dict):
    user = await authenticate(...)
    if not user:
        return rx.toast.error("Bad credentials")
    self.current_user = user
    return [
        rx.toast.success("Welcome back"),
        rx.redirect("/dashboard"),
    ]
```

Common specs: `rx.redirect`, `rx.toast.*`, `rx.window_alert`,
`rx.call_script`, `rx.set_clipboard`, `rx.set_focus`. Lists of specs
execute in order.

## Cross-state access

```python
class UsersState(rx.State):
    async def invite_user(self, email: str):
        # Need current org from OrgState
        org_state = await self.get_state(OrgState)
        await send_invite(email, org_state.current_org_id)
```

`await self.get_state(OtherState)` returns the other state for the
same session. Use for occasional cross-cutting reads/writes; if you're
doing this in half your handlers, your state split has too many
boundaries.

## Lifecycle — `on_load` for per-page fetches

```python
class UserPageState(rx.State):
    user: User | None = None

    async def load(self):
        user_id = self.router.page.params.get("id")
        self.user = await fetch_user(user_id)

@rx.page(route="/users/[id]", on_load=UserPageState.load)
def user_page() -> rx.Component:
    return rx.cond(UserPageState.user,
                   user_detail(UserPageState.user),
                   rx.spinner())
```

Don't fetch in the component body. `on_load` runs server-side once per
page mount and flushes state to the client.

## Debouncing user input

```python
rx.input(
    value=SearchState.query,
    on_change=SearchState.set_query.debounce(300),
    placeholder="Search...",
)
```

`.debounce(ms)` on a setter throttles the client→server event firing. Crucial for search boxes, filter inputs; otherwise every keystroke fires a state event.

## Private fields

If a field should exist in state but not be sent to the client (secrets, internal computation state), prefix with underscore:

```python
class AuthState(rx.State):
    _api_key: str = ''             # server-only, not in client state
    user: User | None = None       # client-visible
```

Private fields can't be bound in templates (by design). Use them for ephemeral server-side work.

## Common pitfalls

- **Mutating a list/dict field in place** and expecting re-render.
- **Forgetting `yield` in async events** — loading states flicker invisibly.
- **Using `@rx.var` for something expensive without `cache=True`** — recomputes on every access.
- **Instantiating state** (`UsersState().users`) instead of referencing the class (`UsersState.users`) — breaks the reactivity wiring.
- **Circular computed vars** — `@rx.var a depends on b, b depends on a` → error at compile.
- **Giant state classes** — slow compile, re-render storms, hard to reason about.
- **Sharing state between sessions** — state is per-session by default. For shared server-side data, use a module-level cache, a DB, or an external store.
- **Using `__init__` on `rx.State`** — don't. Use field defaults or `rx.var` for initialization.

## Shape the API for event handlers clearly

A good state method:

- Takes ≤ 2 args (Reflex passes form data as dict, DOM values as positional).
- Returns event specs OR nothing.
- Mutates fields; doesn't secretly call external services without logging.
- Has a docstring if it's non-obvious.

```python
async def submit_comment(self, form_data: dict):
    """Posts a new comment and clears the compose field."""
    await self.api.post_comment(form_data["text"])
    self.compose_text = ""
    self.comments = [*self.comments, Comment(text=form_data["text"])]
    return rx.toast.success("Comment posted")
```

Methods that do 4 different things should become 4 methods; or extract helpers to keep event handlers thin.
