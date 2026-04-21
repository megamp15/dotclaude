---
source: stacks/angular
name: angular-signals
description: How to use Angular signals correctly — when to reach for signals vs RxJS, computed vs effect, interop, and common mistakes. Load when writing or reviewing signal-based Angular components.
triggers: signal, computed, effect, toSignal, toObservable, onpush, change detection, angular reactivity
globs: ["**/*.ts", "**/*.html"]
---

# Angular signals

Signals are the modern reactivity primitive. They compose better than
`BehaviorSubject`, change-detect precisely (not the whole subtree), and
read like regular values.

## Three primitives

```ts
const count = signal(0);                       // writable
const double = computed(() => count() * 2);    // derived, tracked automatically
effect(() => console.log('count is', count())); // side effect on change
```

Calling a signal reads it: `count()` returns the current value. Setting writes: `count.set(1)` or `count.update(n => n + 1)`.

## When to use what

| Need | Primitive |
|---|---|
| Component-local mutable state | `signal()` |
| Derived / memoized value | `computed()` |
| Side effect (log, DOM, imperative API call) | `effect()` |
| Two-way binding (child updates parent) | `model()` |
| Converting an Observable to a signal | `toSignal(obs$)` |
| Converting a signal to an Observable | `toObservable(sig)` |

## Signals vs RxJS

Use **signals** for:

- Component state (`count`, `selectedId`, `isEditing`, `items`).
- Derived view state (counts, filters, aggregates).
- DOM-driven state that doesn't need time-based composition.

Use **RxJS** for:

- HTTP and WebSocket streams.
- Debounced inputs, typeahead, retries with backoff.
- Combining multiple event streams with time semantics.

Interop both ways works:

```ts
// HTTP stream → signal for template consumption
readonly user = toSignal(
  this.http.get<User>('/api/user').pipe(retry(2)),
  { initialValue: null }
);

// Signal → Observable for debounced search
readonly query = signal('');
readonly results$ = toObservable(this.query).pipe(
  debounceTime(250),
  distinctUntilChanged(),
  switchMap(q => this.search(q))
);
```

## `effect()` — the footgun

Effects run during change detection. They can trigger writes to other signals (by default, disallowed — Angular warns).

Rules:

- **Prefer `computed()`** for derived values. Effects are for side effects outside the reactive graph.
- **Don't write to a signal from inside an effect** unless you've set `{ allowSignalWrites: true }` and you've thought hard about why.
- **Clean up** manual subscriptions / timers / DOM listeners the effect creates — pass a teardown function:

```ts
effect((onCleanup) => {
  const id = setInterval(() => count.update(n => n + 1), 1000);
  onCleanup(() => clearInterval(id));
});
```

- Effects outside injection context need an explicit injector: `effect(() => ..., { injector })`.

## `computed()` is lazy and memoized

```ts
const expensive = computed(() => heavyCalc(source()));
```

`expensive()` only runs `heavyCalc` when `source()` changes AND something is currently reading `expensive()`. If nothing reads it, it doesn't recompute — even if the source changes.

Don't worry about `computed()` performance for straightforward derivations. Do worry if `heavyCalc` is expensive AND is read in many templates (same value is shared, no recomputation).

## `model()` for two-way binding

```ts
// Child
@Component({ ... })
class DatePicker {
  value = model<Date>();   // two-way
}

// Parent template
<date-picker [(value)]="selectedDate" />
```

Parent's `selectedDate` is a signal; child's `value` is a model signal; they stay in sync automatically. Cleaner than `@Input()` + `@Output() valueChange`.

## Signal inputs (`input()`)

Angular 17.3+:

```ts
@Component({ ... })
class UserCard {
  user = input.required<User>();      // required
  variant = input<'compact' | 'full'>('full');  // optional with default
}
```

Inputs are now signals. Template reads: `{{ user().name }}`. Reactive: when parent changes the bound value, the child's signal updates; computed/effect/template re-read automatically.

This obsoletes `ngOnChanges` for most cases. `computed()` on inputs handles derived props declaratively.

## Common mistakes

### Calling signal without `()` in template

```html
<!-- WRONG: shows function reference, not value -->
<p>{{ count }}</p>

<!-- RIGHT -->
<p>{{ count() }}</p>
```

### Forgetting `track` on `@for`

```html
<!-- WRONG: Angular errors at build time (required) -->
@for (item of items()) { ... }

<!-- RIGHT -->
@for (item of items(); track item.id) { ... }
```

### Writing signals from effects

```ts
// BAD
effect(() => {
  if (user()) count.set(user()!.orders.length);
});

// GOOD
readonly count = computed(() => user()?.orders.length ?? 0);
```

If you're writing a signal from an effect, you usually want `computed()` instead.

### `OnPush` with non-signal state

OnPush change detection only fires on:
- `@Input()` reference changes
- Events from the template
- Observables via `async` pipe
- Signal reads in the template

If you mutate an object field without changing the reference, OnPush won't re-render. With signals, use `.update()` and return a new object:

```ts
// BAD
const user = signal({ name: 'a', orders: [] });
user().orders.push(newOrder);   // mutates; no re-render

// GOOD
user.update(u => ({ ...u, orders: [...u.orders, newOrder] }));
```

### Overusing signals

Not everything needs to be a signal. A component-local value that never changes can be a plain field. A constant is a constant.

## Testing signals

Signals read synchronously in tests — no `fakeAsync` needed for pure-signal logic:

```ts
const c = signal(0);
expect(c()).toBe(0);
c.set(5);
expect(c()).toBe(5);

const d = computed(() => c() * 2);
expect(d()).toBe(10);
```

For effects, you need an injection context:

```ts
TestBed.runInInjectionContext(() => {
  effect(() => { /* ... */ });
});
```

Drive change detection with `fixture.detectChanges()` as usual for component tests.
