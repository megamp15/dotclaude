---
name: angular-architect
description: Deep Angular 17+ expertise — standalone component design, signals vs. RxJS decisions, NgRx store + effects + selectors, typed reactive forms, router guards/resolvers as functions, and bundle performance. Extends the rules in `stacks/angular/CLAUDE.stack.md`.
source: stacks/angular
triggers: /angular-architect, Angular 17, Angular 18, Angular 19, standalone component, signal, computed, effect, NgRx, createFeature, createEffect, RxJS, Angular router, CanActivateFn, Angular performance, Angular testing, zoneless
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/angular-architect
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# angular-architect

You design and implement Angular 17+ features at enterprise scale. The
baseline conventions already live in
`stacks/angular/CLAUDE.stack.md` — read that first. This skill is for
the decisions that don't fit in a style guide: architecture, state flow,
async patterns, performance triage.

## When this skill is the right tool

- Designing the component + state shape for a new feature
- Choosing **signals vs. RxJS vs. NgRx** per feature
- Setting up or refactoring an NgRx store (actions / reducer / effects /
  selectors / entity adapter)
- Configuring routing: lazy loading, `CanActivateFn` / `ResolveFn`,
  component input binding
- Triaging change-detection + bundle regressions

**Not for:**
- Baseline conventions already in `CLAUDE.stack.md` — read that first.
- Backend work — pair with the appropriate backend stack skill.

## Core workflow

1. **Analyze.** Component tree, state shape, routing, async boundaries.
2. **Design.** Pick state mechanism per slice (local signal / shared
   service signal / NgRx feature store). Decide routing + guards.
3. **Implement.**
   - Standalone components, `OnPush`, signals + `input()` / `output()` /
     `model()` where available.
   - Services provided at the right scope (`'root'` vs. component).
   - NgRx only when the state is genuinely shared + long-lived + benefits
     from time-travel/devtools.
4. **Typecheck.** Strict mode + strict templates.
5. **Optimize.** Deferred loading, bundle audit, signals over RxJS for
   component reactivity.
6. **Test.** TestBed + behavior assertions, not implementation.

## State decision tree

```
Where does this state live?
 └─ Inside one component only
      └─ signal()  (or computed() if derived)
 └─ Shared among a few related components (same feature)
      └─ Service provided at the feature's route component, exposing signals
 └─ Shared across features / long-lived / needs time-travel + devtools
      └─ NgRx feature store (createFeature, effects, selectors)
 └─ Server data (HTTP / WS)
      └─ Service using HttpClient, expose toSignal() for consumers
```

Resist NgRx-by-default. A lot of apps are fine with signals + services.
NgRx shines when you have cross-cutting state, complex effects, or an
existing Redux culture.

## Standalone component anatomy

```ts
import {
  ChangeDetectionStrategy,
  Component,
  computed,
  inject,
  input,
  output,
  signal,
} from "@angular/core";
import { CommonModule } from "@angular/common";

@Component({
  selector: "app-user-card",
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (user(); as u) {
      <section>
        <h2>{{ u.name }}</h2>
        <p>{{ u.email }}</p>
        <button type="button" (click)="onSelect()">Select</button>
      </section>
    } @else {
      <p>Loading…</p>
    }
  `,
})
export class UserCardComponent {
  user = input.required<User>();
  selected = output<User>();

  initials = computed(() => this.user().name.split(" ").map(p => p[0]).join(""));

  onSelect(): void {
    this.selected.emit(this.user());
  }
}
```

Highlights:
- `standalone: true` + `imports`.
- `OnPush` change detection.
- `input.required<T>()` for required inputs (throws at runtime if missing).
- `output<T>()` replaces `@Output() EventEmitter`.
- Template uses modern `@if` / `@for` control flow.

## Signals — the essentials

- `signal(initial)` — writable value.
- `computed(() => …)` — derived; auto-tracks signal reads; memoized.
- `effect(() => …)` — side effects on change; runs inside the injection
  context.
- `input()`, `output()`, `model()` — I/O primitives.
- `toSignal(obs$)`, `toObservable(sig)` — RxJS interop.

Rules:
- Prefer `computed()` for derivations, `effect()` for side effects.
- Effects are **not free** — they run during change detection. Don't put
  expensive work in one.
- Don't set a signal inside a `computed()` — causes warnings and loops.

## RxJS — where it earns its weight

Keep RxJS for what it's good at:
- HTTP, WebSocket, SSE streams.
- Cancellation (`switchMap` typeahead).
- Debounce / throttle / merge / scan on user input or streams.

Don't use RxJS for:
- Component-local booleans (use signals).
- Parent → child communication (use inputs).

### Subscription hygiene

```ts
import { Component, DestroyRef, inject } from "@angular/core";
import { takeUntilDestroyed } from "@angular/core/rxjs-interop";

@Component({ /* … */ })
export class SearchComponent {
  private users = inject(UsersService);
  private destroyRef = inject(DestroyRef);

  ngOnInit(): void {
    this.users
      .list$()
      .pipe(takeUntilDestroyed(this.destroyRef))
      .subscribe({
        next: (list) => { /* … */ },
        error: (err) => console.error(err),
      });
  }
}
```

Prefer the `async` pipe in the template when it fits — it handles
subscribe/unsubscribe automatically and plays nicely with `OnPush`.

## NgRx — when and how

Use NgRx when the state is:
- Shared across unrelated features or routes.
- Long-lived (survives feature navigation).
- Complex enough to benefit from reducers + effects + devtools time
  travel.

### Feature with `createFeature`

```ts
import { createFeature, createReducer, on } from "@ngrx/store";
import { UsersActions } from "./users.actions";

export interface UsersState {
  entities: User[];
  loading: boolean;
  error: string | null;
}

const initialState: UsersState = { entities: [], loading: false, error: null };

export const usersFeature = createFeature({
  name: "users",
  reducer: createReducer(
    initialState,
    on(UsersActions.load, (s) => ({ ...s, loading: true, error: null })),
    on(UsersActions.loadSuccess, (s, { users }) => ({
      ...s,
      entities: users,
      loading: false,
    })),
    on(UsersActions.loadFailure, (s, { error }) => ({
      ...s,
      loading: false,
      error,
    })),
  ),
});

export const {
  name: usersFeatureKey,
  reducer: usersReducer,
  selectEntities: selectUsers,
  selectLoading: selectUsersLoading,
  selectError: selectUsersError,
} = usersFeature;
```

`createFeature` auto-generates selectors — no manual `createSelector`
boilerplate for root-level state slices.

### Effects

```ts
import { inject, Injectable } from "@angular/core";
import { Actions, createEffect, ofType } from "@ngrx/effects";
import { catchError, map, of, switchMap } from "rxjs";

@Injectable()
export class UsersEffects {
  private actions$ = inject(Actions);
  private api = inject(UsersApi);

  load$ = createEffect(() =>
    this.actions$.pipe(
      ofType(UsersActions.load),
      switchMap(() =>
        this.api.list().pipe(
          map((users) => UsersActions.loadSuccess({ users })),
          catchError((err) => of(UsersActions.loadFailure({ error: String(err) }))),
        ),
      ),
    ),
  );
}
```

Guidelines:
- One effect per action flow. Don't pile unrelated flows into one stream.
- Always handle errors with `catchError` inside `switchMap` — don't kill
  the outer stream.
- Don't dispatch from reducers; only from effects.

### Entity adapter (for lists)

```ts
import { createEntityAdapter, EntityState } from "@ngrx/entity";

export interface UsersState extends EntityState<User> {
  loading: boolean;
  error: string | null;
}

export const adapter = createEntityAdapter<User>({
  selectId: (u) => u.id,
  sortComparer: (a, b) => a.name.localeCompare(b.name),
});

export const initialState: UsersState = adapter.getInitialState({
  loading: false,
  error: null,
});
```

Use entity adapter for any normalized collection. Beats hand-rolled
`id -> entity` maps.

## Routing — functional guards + component inputs

```ts
// app.routes.ts
import { Routes } from "@angular/router";
import { authGuard } from "./auth/auth.guard";
import { productResolver } from "./products/product.resolver";

export const routes: Routes = [
  {
    path: "dashboard",
    canActivate: [authGuard],
    loadChildren: () => import("./dashboard/routes").then((m) => m.dashboardRoutes),
  },
  {
    path: "products/:id",
    loadComponent: () => import("./products/product-detail.component").then((m) => m.ProductDetailComponent),
    resolve: { product: productResolver },
  },
];
```

```ts
// auth.guard.ts
import { CanActivateFn, Router } from "@angular/router";
import { inject } from "@angular/core";
import { AuthService } from "./auth.service";

export const authGuard: CanActivateFn = () => {
  const auth = inject(AuthService);
  const router = inject(Router);
  return auth.isLoggedIn() ? true : router.createUrlTree(["/login"]);
};
```

```ts
// main.ts
provideRouter(routes, withComponentInputBinding())
```

With `withComponentInputBinding()`, route params flow as component
inputs — no more `ActivatedRoute` boilerplate in most components.

## Reactive forms — typed

```ts
import { FormBuilder, Validators } from "@angular/forms";
import { inject } from "@angular/core";

const fb = inject(FormBuilder).nonNullable;

const form = fb.group({
  email: fb.control("", { validators: [Validators.required, Validators.email] }),
  password: fb.control("", { validators: [Validators.required, Validators.minLength(8)] }),
});

// typed value:
form.value; // { email: string; password: string }
```

`FormBuilder.nonNullable` is the ergonomic default for typed forms.

## Performance triage

1. **OnPush everywhere.** If a component is re-rendering on every CD,
   it's almost always missing `OnPush`.
2. **`track` on every `@for`.** `track item.id`, not `track $index`.
3. **Defer below-the-fold**: `@defer { <heavy /> } @placeholder {
   <lite /> }`.
4. **Signals over RxJS** for component reactivity reduces CD cost.
5. **Bundle**: `ng build --configuration production` and check per-chunk
   sizes. Lazy-load heavy features.
6. **No impure pipes** unless strictly necessary.
7. **Measure** with `ng build --stats-json` + source-map-explorer, or
   Angular DevTools Profiler.

## Testing

- **Unit**: TestBed + shallow rendering; assert observable behavior
  (rendered text, emitted events), not private method calls.
- **HTTP**: `HttpClientTestingModule`; flush requests explicitly —
  unflushed requests should fail the test.
- **Signals**: test by reading the signal after driving inputs.
- **E2E**: Playwright or Cypress; `ng e2e` with Cypress is the common
  default.
- Coverage target: ≥ 80–85% for application code; ≥ 95% for shared
  libraries.

## Rules

### Must do

- Standalone components, `OnPush`, strict mode, strict templates.
- `track` on every `@for`.
- `takeUntilDestroyed()` (or `async` pipe) for every subscription.
- `CanActivateFn` + `ResolveFn` (functional guards/resolvers).
- `FormBuilder.nonNullable` for typed reactive forms.
- `provideRouter(routes, withComponentInputBinding())`.
- NgRx `createFeature` / `createEntityAdapter` when using NgRx.

### Must not

- `NgModule` for new code (except when a library requires it).
- Class-based guards / resolvers.
- `@Input()` / `@Output()` decorators where `input()` / `output()` are
  available.
- Untyped forms, untyped HTTP responses.
- Any-typed state, `any`-typed NgRx actions.
- Subscriptions without teardown.
- NgRx when signals + a service would do.

## References

| Topic | File |
|---|---|
| Standalone components, signals, input/output | `references/components.md` |
| RxJS — when to use, operators, error handling | `references/rxjs.md` |
| NgRx — store, effects, selectors, entity adapter | `references/ngrx.md` |
| Routing — functional guards, resolvers, lazy loading | `references/routing.md` |
| Testing — TestBed, signals, HTTP, NgRx | `references/testing.md` |

## See also

- Baseline Angular rules → `stacks/angular/CLAUDE.stack.md`
- Full-stack feature flow → `core/skills/fullstack-guardian`
- API design for the backend → `core/skills/api-designer`
