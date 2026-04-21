---
source: stacks/angular
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/angular-architect/references/rxjs.md
ported-at: 2026-04-17
adapted: true
---

# RxJS — when and how

Use RxJS for async streams with real temporal semantics: HTTP, WS, SSE,
debounced user input, cancellation. Don't use it as a general
state-management library.

## Operators you actually need

| Goal | Operator |
|---|---|
| Map values | `map` |
| Filter | `filter` |
| Side effect (logging) | `tap` |
| Latest pending request only (cancel older) | `switchMap` |
| Keep older, queue new | `concatMap` |
| Run in parallel | `mergeMap` |
| Skip if already in flight | `exhaustMap` |
| Time-based dedup of user input | `debounceTime` |
| Rate-limit | `throttleTime` |
| Dedup of identical values | `distinctUntilChanged` |
| Combine latest values from N streams | `combineLatest` |
| Pair events with latest value from another | `withLatestFrom` |
| Retry with delay | `retry({ count, delay })` |
| Error → fallback | `catchError` |
| Timeout | `timeout` |
| Complete on signal | `takeUntil` / `takeUntilDestroyed()` |

## Typeahead (the canonical example)

```ts
import { debounceTime, distinctUntilChanged, switchMap } from "rxjs";

queryChange$
  .pipe(
    debounceTime(200),
    distinctUntilChanged(),
    switchMap((q) => this.api.search(q)),
    takeUntilDestroyed(),
  )
  .subscribe((results) => this.results.set(results));
```

`switchMap` is the key — it cancels the previous request when a new
query arrives. Without it, a slow earlier response can overwrite a
fresh one.

## HTTP with retries + timeout

```ts
this.http.get<User[]>("/api/users", { context: traced("users.list") })
  .pipe(
    timeout(5_000),
    retry({ count: 2, delay: (err, i) => timer(i * 300) }),
    catchError((err) => {
      this.log.error("users.list failed", err);
      return of([] as User[]);
    }),
  );
```

Rules:
- `timeout` + `retry` is a better default than hope.
- `catchError` returns a fallback observable — don't swallow silently.
- Log before fallback.

## WebSocket / SSE

```ts
import { webSocket } from "rxjs/webSocket";

const socket$ = webSocket<ChatMsg>("wss://api.example.com/chat");

socket$
  .pipe(
    retry({ count: 5, delay: (_, i) => timer(1000 * 2 ** i) }),
    takeUntilDestroyed(),
  )
  .subscribe({
    next: (msg) => this.messages.update((m) => [...m, msg]),
    error: (err) => this.connected.set(false),
  });
```

For SSE, use a service that wraps `EventSource` and exposes an
observable.

## Error handling patterns

### Per-request fallback

```ts
this.api.get().pipe(
  catchError(() => of(defaultValue)),
);
```

### Explicit failure state

```ts
this.api.get().pipe(
  map((data) => ({ kind: "ok" as const, data })),
  catchError((error) => of({ kind: "err" as const, error })),
);
```

Templates react to `kind` — cleaner than try/catch.

### Retry with exponential backoff

```ts
retry({
  count: 3,
  delay: (err, attempt) => timer(1000 * 2 ** attempt),
});
```

## Subscription hygiene — no leaks

Three good patterns, pick per context:

1. **`async` pipe** — best when the value is consumed only in the
   template. Auto-subscribe + auto-teardown.

   ```html
   @if (users$ | async; as users) {
     <app-user-list [users]="users" />
   }
   ```

2. **`takeUntilDestroyed()`** — inside a component that needs to
   subscribe imperatively.

   ```ts
   inject(AuthService).session$.pipe(takeUntilDestroyed()).subscribe(...);
   ```

3. **`toSignal()`** — when you want signal consumers. Integrates with
   `computed()`.

   ```ts
   user = toSignal(this.userService.current$, { initialValue: null });
   ```

Don't leave raw `.subscribe()` without teardown — that's a memory leak.

## Signals ⟷ RxJS interop

- `toSignal(obs$)` — subscribe once, expose as a signal. Supports
  `initialValue`, `requireSync`, and `injector` options.
- `toObservable(sig)` — turn a signal into an observable. Fires when
  the signal changes.

Pattern: **use signals for component state and template reads; use RxJS
for event streams and async orchestration.** Connect the two at the
boundary.

## Subject types

| Subject | Emits to new subscribers |
|---|---|
| `Subject` | nothing before subscription |
| `BehaviorSubject` | current value on subscribe |
| `ReplaySubject(n)` | last N values |
| `AsyncSubject` | final value on complete |

`BehaviorSubject` is the default for "current state + change notifications"
in service layers — though `signal()` is often simpler now.

## Gotchas

### Operators in the wrong place

```ts
// BAD — catchError above switchMap kills the whole stream on first error
source$.pipe(catchError(() => EMPTY), switchMap(fetch));

// GOOD — catchError inside switchMap protects one request at a time
source$.pipe(switchMap((q) => fetch(q).pipe(catchError(() => EMPTY))));
```

### Cold vs. hot observables

HTTP observables are **cold** — each `subscribe` triggers a new request.
Wrap with `shareReplay({ bufferSize: 1, refCount: true })` to share.

### `subscribe` inside `subscribe`

```ts
// BAD
a$.subscribe((a) => b$.subscribe((b) => ...));

// GOOD
a$.pipe(switchMap((a) => b$)).subscribe(...);
```

Flatten with the right `*Map` operator.

### `tap` for side effects only

Don't mutate the stream inside `tap`. It's read-only. Use `map` for
transformations.

## When NOT to use RxJS

- Component-local booleans, counters, selection state → `signal()`.
- Parent → child data → inputs (signals).
- Global app state → NgRx or signal-based service.
- One-shot async → just `await` (with `firstValueFrom`/`lastValueFrom`
  if starting from an observable).
