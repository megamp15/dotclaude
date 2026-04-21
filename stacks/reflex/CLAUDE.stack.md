---
source: stacks/reflex
---

# Stack: Reflex

[Reflex](https://reflex.dev) (formerly Pynecone) — full-stack web apps
written in pure Python. Frontend compiles to React/Next.js; backend is
FastAPI. Layers on top of `core/` and `stacks/python`.

## Mental model

- **You write Python.** Components are Python classes/functions; events are Python methods; state is a Python class with typed fields.
- **Reflex compiles** your Python to a React frontend + a FastAPI backend. You run `reflex run` in dev, `reflex export` for prod.
- **State lives on the server by default.** Components render against state; events mutate state; the frontend WebSocket-syncs the mutated fields.

This is not "Python that writes HTML strings" (that's Jinja/htmx). This is a Python API that produces a compiled SPA. The reactivity model is closer to React's than to Django's.

## When Reflex is the right pick

- Pure-Python shops that want richer interactivity than Jinja+HTMX offer without bringing in JS tooling.
- Dashboards, admin consoles, internal tools with some real interactivity.
- Prototyping LLM / ML tooling where the dev is Python-first.
- Cases where server-side state ownership + automatic sync is the right trade.

When it's the wrong pick:

- Heavy client-side state (editors, graphics tools, games). The server round-trip isn't free; complex UIs will feel slower than a pure SPA.
- Apps where you need specific JS ecosystem libraries Reflex doesn't wrap.
- Offline-first or PWAs.
- When the team is already productive in React/Vue/Angular — the rewrite-to-Reflex cost doesn't pay back.

## Project structure

```
my_app/
├── rxconfig.py                   # Reflex config (app name, plugins, deploy targets)
├── requirements.txt / pyproject
├── my_app/
│   ├── __init__.py
│   ├── my_app.py                 # app entry: rx.App, pages
│   ├── state.py                  # rx.State subclasses
│   ├── pages/
│   │   ├── index.py              # @rx.page decorator on components
│   │   └── dashboard.py
│   ├── components/               # reusable component functions
│   │   ├── navbar.py
│   │   └── data_table.py
│   ├── models.py                 # rx.Model ORM (SQLModel-backed)
│   └── styles.py                 # theme, shared styles
└── assets/                       # static files served by the frontend
```

Keep state, pages, components, and models separated. A single monolithic `my_app.py` works for 2-page demos; anything bigger, split.

## State

`rx.State` is the core pattern. Typed fields; methods mutate fields; the frontend re-renders bound components.

```python
class CounterState(rx.State):
    count: int = 0
    items: list[str] = []

    def increment(self):
        self.count += 1

    def add_item(self, form_data: dict):
        self.items = [*self.items, form_data["name"]]
```

**Rules that bite:**

- **Type every field.** Reflex uses type hints to generate the frontend. `list` is insufficient; use `list[str]` or `list[MyModel]`. Missing/loose types = runtime or compile errors.
- **Immutable updates.** `self.items.append(...)` doesn't trigger re-render in all cases. Assign a new list: `self.items = [*self.items, new]`.
- **Computed vars** with `@rx.var` — derived values that recompute when dependencies change:
  ```python
  @rx.var
  def total(self) -> int:
      return sum(item.price for item in self.items)
  ```
- **Async event handlers** are fine — Reflex supports `async def increment()`. Use for HTTP calls, DB queries.
- **Background events** (`@rx.event(background=True)`) run outside the normal lock; useful for long-running tasks that yield progress updates.

## State hierarchy and scoping

- **One root `rx.State`** for app-wide data (user, theme).
- **Subclasses** (`class DashboardState(rx.State)`) scope fields to a page or feature. Reflex instantiates state per-session.
- **Avoid one giant State class** — split along feature boundaries.
- **Cross-state access**: `other_state = await self.get_state(OtherState)` inside an event handler. Use sparingly; if you need this a lot, your state split is wrong.

## Components

Two ways:

```python
# Function component
def greeting(name: str) -> rx.Component:
    return rx.text(f"Hello, {name}", size="4")

# Binding to state
def counter() -> rx.Component:
    return rx.vstack(
        rx.text(CounterState.count),               # auto-updates
        rx.button("+", on_click=CounterState.increment),
    )
```

- **Don't pass state to components as arguments** for dynamic binding — reference the class attribute directly: `CounterState.count`, not `CounterState().count`.
- **`cond`, `foreach`** for reactive conditionals and lists:
  ```python
  rx.cond(State.logged_in, dashboard(), login_form())
  rx.foreach(State.items, lambda item: rx.text(item))
  ```
  A plain `if` in a component body runs at compile time, not per render; use `rx.cond` when the branch depends on state.

## Styling

- **Radix Themes** backing — `rx.theme(...)` on the app sets color scale, radius, accent.
- **Inline props** for one-offs: `rx.text("Hi", font_size="2em", color="blue")`.
- **Tailwind plugin** (`rx.plugins.TailwindV3Plugin`) if you want utility-class styling.
- **Themed tokens** — reach for `rx.color("accent", 9)` etc. instead of raw hex for theme-aware colors.

## Database — `rx.Model`

`rx.Model` wraps SQLModel:

```python
class User(rx.Model, table=True):
    email: str
    name: str
```

- Migrations: `reflex db makemigrations` / `reflex db migrate` (Alembic underneath).
- For anything non-trivial, either use `rx.Model` consistently or bypass it with direct SQLModel/SQLAlchemy — mixing causes friction.
- Production: a real DB (Postgres); dev default is SQLite.

## Events and forms

```python
def login_form() -> rx.Component:
    return rx.form(
        rx.input(name="email", placeholder="email@example.com"),
        rx.input(name="password", type="password"),
        rx.button("Log in", type="submit"),
        on_submit=AuthState.login,
        reset_on_submit=True,
    )

class AuthState(rx.State):
    async def login(self, form_data: dict):
        user = await authenticate(form_data["email"], form_data["password"])
        if not user:
            return rx.toast.error("Invalid credentials")
        self.user_id = user.id
        return rx.redirect("/dashboard")
```

- Event handlers **return `rx.Component`-like event specs** (`rx.redirect`, `rx.toast`, `rx.window_alert`, etc.) to trigger side-effects.
- Return lists of events for multi-step side effects.

## Pages and routing

```python
@rx.page(route="/users/[id]", title="User detail")
def user_page() -> rx.Component:
    # State.router.page.params["id"] — URL param
    return rx.text(UserState.current_user.name)
```

- **Dynamic segments** via `[param]`.
- **`on_load` event handlers** fetch per-page data:
  ```python
  @rx.page(route="/users", on_load=UserState.load_users)
  def users_list() -> rx.Component: ...
  ```

## Testing

- **Backend logic** (state methods): pytest + instantiate the State class directly, call the methods, assert on fields. No browser needed.
- **E2E**: Playwright driving the running app — treat it like any web app.
- **Compile-time errors** — `reflex compile` / `reflex run` catches many type mismatches early. Run it in CI.

## Performance and scaling

- **State is per-session**; each user gets their own instance. Scales horizontally as long as state doesn't overflow memory or hit DB too hard.
- **Large lists / tables** — use pagination; don't stream 10k items to the frontend on every re-render.
- **`@rx.var(cache=True)`** for expensive computed vars — caches per-state-instance.
- **Avoid heavy work in render** — precompute in state or computed var.

## Do not

- Do not mix Jinja templates with Reflex components. Pick the rendering model; don't straddle.
- Do not skip type annotations on state fields — the frontend compiler needs them.
- Do not mutate state lists/dicts in place; reassign.
- Do not expose sensitive data via state fields — state is sent to the client when bound. Mark private fields with leading underscore if they must exist in state but not render.
- Do not treat `rx.State` as a session store for arbitrary blobs. It's reactive UI state; large persistent data goes in the DB.
- Do not use `print()` for logging in production — Reflex integrates with `logging`; use it.
