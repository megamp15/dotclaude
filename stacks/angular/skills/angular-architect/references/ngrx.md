---
source: stacks/angular
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/angular-architect/references/ngrx.md
ported-at: 2026-04-17
adapted: true
---

# NgRx

Use NgRx when state is genuinely **shared + long-lived + complex enough
to benefit from devtools/time-travel**. For most feature-local state,
signals + a service are simpler.

## Folder shape

```
src/app/features/users/
├── users.actions.ts
├── users.effects.ts
├── users.feature.ts         # createFeature (reducer + auto selectors)
├── users.selectors.ts       # extra hand-rolled selectors
└── users.api.ts             # HTTP service
```

## Actions with `createActionGroup`

```ts
import { createActionGroup, emptyProps, props } from "@ngrx/store";

export const UsersActions = createActionGroup({
  source: "Users",
  events: {
    load: emptyProps(),
    "load success": props<{ users: User[] }>(),
    "load failure": props<{ error: string }>(),
    "create": props<{ payload: CreateUser }>(),
    "create success": props<{ user: User }>(),
    "create failure": props<{ error: string }>(),
    "select": props<{ id: string }>(),
  },
});
```

Use `createActionGroup` over `createAction` — eliminates naming drift
and keeps action types centralized.

## Feature with `createFeature`

```ts
import { createFeature, createReducer, on } from "@ngrx/store";
import { createEntityAdapter, EntityState } from "@ngrx/entity";

export interface UsersState extends EntityState<User> {
  loading: boolean;
  error: string | null;
  selectedId: string | null;
}

export const adapter = createEntityAdapter<User>({
  selectId: (u) => u.id,
  sortComparer: (a, b) => a.name.localeCompare(b.name),
});

export const initialState: UsersState = adapter.getInitialState({
  loading: false,
  error: null,
  selectedId: null,
});

export const usersFeature = createFeature({
  name: "users",
  reducer: createReducer(
    initialState,
    on(UsersActions.load, (s) => ({ ...s, loading: true, error: null })),
    on(UsersActions.loadSuccess, (s, { users }) =>
      adapter.setAll(users, { ...s, loading: false }),
    ),
    on(UsersActions.loadFailure, (s, { error }) => ({ ...s, loading: false, error })),
    on(UsersActions.select, (s, { id }) => ({ ...s, selectedId: id })),
    on(UsersActions.createSuccess, (s, { user }) => adapter.addOne(user, s)),
  ),
  extraSelectors: ({ selectUsersState, selectSelectedId }) => {
    const { selectAll } = adapter.getSelectors(selectUsersState);
    return {
      selectAllUsers: selectAll,
      selectSelectedUser: createSelector(
        selectAll,
        selectSelectedId,
        (users, id) => users.find((u) => u.id === id) ?? null,
      ),
    };
  },
});

export const {
  name: usersFeatureKey,
  reducer: usersReducer,
  selectLoading,
  selectError,
  selectSelectedId,
  selectAllUsers,
  selectSelectedUser,
} = usersFeature;
```

`createFeature` auto-generates base selectors (`selectXxxState`,
`selectLoading`, …). Use `extraSelectors` for derived ones.

## Effects

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

  create$ = createEffect(() =>
    this.actions$.pipe(
      ofType(UsersActions.create),
      concatMap(({ payload }) =>
        this.api.create(payload).pipe(
          map((user) => UsersActions.createSuccess({ user })),
          catchError((err) => of(UsersActions.createFailure({ error: String(err) }))),
        ),
      ),
    ),
  );
}
```

Rules:
- **`catchError` inside** the inner `switchMap` / `concatMap`. Outside
  it, the outer stream dies on first error.
- Pick the right flattening operator:
  - `switchMap` — cancel old (typeahead, GETs).
  - `concatMap` — queue (writes that mustn't reorder).
  - `mergeMap` — parallel (independent writes).
  - `exhaustMap` — ignore new while one in flight (login button spam).
- One effect per action flow.
- Non-dispatching effect: `createEffect(() => …, { dispatch: false })`.

## Registering feature state

```ts
// users.providers.ts
import { provideState } from "@ngrx/store";
import { provideEffects } from "@ngrx/effects";
import { usersFeature } from "./users.feature";
import { UsersEffects } from "./users.effects";

export const usersProviders = [
  provideState(usersFeature),
  provideEffects(UsersEffects),
];
```

Register at the route that owns the feature (lazy-loaded), or in
`app.config.ts` for global state.

## Consuming in components

```ts
import { Store } from "@ngrx/store";
import { toSignal } from "@angular/core/rxjs-interop";
import { UsersActions, selectAllUsers, selectLoading } from "@/features/users";

@Component({ /* … */ })
export class UsersPage {
  private store = inject(Store);

  users = toSignal(this.store.select(selectAllUsers), { initialValue: [] });
  loading = toSignal(this.store.select(selectLoading), { initialValue: false });

  load() { this.store.dispatch(UsersActions.load()); }
  select(id: string) { this.store.dispatch(UsersActions.select({ id })); }
}
```

Prefer signals for consumption — cleaner templates + `OnPush` friendly.

## Store devtools

```ts
// app.config.ts
provideStoreDevtools({ maxAge: 50, connectInZone: false, trace: false })
```

Use Redux DevTools in the browser to inspect actions, state, and time-
travel.

## Anti-patterns

- **Lots of boilerplate for simple state.** If actions + reducer +
  effects + selectors are more code than the feature, don't use NgRx.
- **Dispatching from inside a reducer.** Reducers must be pure — no
  side effects. Move the side effect to an effect.
- **Selectors doing heavy computation unmemoized.** Use `createSelector`
  so results are memoized per input.
- **Subscribing to the store inside effects.** Use `concatLatestFrom`
  or `withLatestFrom` to read state within a stream.
- **Mutating state.** Return new objects — use spread, `adapter.*`
  helpers, or Immer (`createReducer` with `mutable` flag, rarely needed).
- **Putting server cache in NgRx.** NgRx is for app state. For server
  cache, reach for dedicated solutions (Apollo, TanStack Query for
  Angular, or a thin HTTP cache service).

## When signals + a service beat NgRx

```ts
@Injectable({ providedIn: "root" })
export class UsersStore {
  private api = inject(UsersApi);

  users = signal<User[]>([]);
  loading = signal(false);
  error = signal<string | null>(null);

  async load() {
    this.loading.set(true);
    this.error.set(null);
    try {
      this.users.set(await firstValueFrom(this.api.list()));
    } catch (e) {
      this.error.set(String(e));
    } finally {
      this.loading.set(false);
    }
  }
}
```

Half the code, no new library, full type safety. Reach for NgRx when
the benefits (devtools, action-based debugging, effects orchestration)
are actually needed.
