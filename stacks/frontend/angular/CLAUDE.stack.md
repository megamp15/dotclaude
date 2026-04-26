---
source: stacks/angular
---

# Stack: Angular

Modern Angular conventions. Layers on top of `core/` and `stacks/node-ts`.
Read those first.

## Version assumption

Target **Angular 17+ (ideally 18/19)** — the era of:

- **Standalone components** (no NgModules for new code)
- **Signals** for reactive state
- **`@if` / `@for` / `@switch` control flow** (replacing `*ngIf` / `*ngFor`)
- **`inject()` function** for DI (alongside constructor injection)
- **`ChangeDetectionStrategy.OnPush`** by default

If the project is Angular 14 or earlier, these rules don't map cleanly; recommend an upgrade first.

## Components

- **Standalone by default.** `@Component({ standalone: true, imports: [...] })`. No new NgModules except where library/lazy-route boundaries demand.
- **One component per file.** Co-located `.html`, `.scss`, `.ts`, `.spec.ts`.
- **`OnPush` change detection** on every component unless you have a specific reason otherwise. With signals and `async` pipe, the default should be OnPush; zone.js full-dirty-check is the exception, not the rule.
- **Smart vs dumb components** — routed components coordinate + fetch, leaf components take inputs + emit outputs. Keep leaf components free of services and HTTP.
- **Inputs + outputs as signals** (Angular 17.3+): `input()`, `output()`, `model()`. Don't use `@Input()` / `@Output()` decorator for new code unless stuck on older versions.

## Control flow

```html
<!-- New (Angular 17+) -->
@if (user(); as u) {
  <div>{{ u.name }}</div>
} @else {
  <div>Loading…</div>
}

@for (item of items(); track item.id) {
  <li>{{ item.label }}</li>
}

@switch (mode()) {
  @case ('edit') { <app-edit /> }
  @case ('view') { <app-view /> }
}
```

**`@for` requires `track`** — always provide a stable identity. `track $index` is legal but almost always wrong; use a record ID.

The old `*ngIf` / `*ngFor` / `ngSwitch` still work but are deprecated — migrate new code.

## Signals — the modern reactivity primitive

- `signal(initial)` for writable values.
- `computed(() => ...)` for derived values — dependencies tracked automatically.
- `effect(() => ...)` for side effects; runs on signal changes.
- `toSignal(obs$)` / `toObservable(sig)` to interop with RxJS.

**Prefer signals over RxJS for component state.** Component-local state that only fires events on user interaction is a bad fit for RxJS's complex operator graph. Use signals; reach for RxJS when the stream semantics (debounce, merge, retry, etc.) earn it.

**Effects are not free.** They run in change detection. Avoid heavy work; prefer `computed()` for derivations. Use `effect()` for DOM side effects, logging, or imperative APIs.

## RxJS — when to use, when not

Use RxJS when:

- Consuming HTTP / Server-Sent Events / WebSockets.
- Composing async events with debounce, throttle, switchMap, retry, withLatestFrom.
- Cancelation matters (search inputs, typeahead).

Don't use RxJS for:

- Simple component state. Signals are simpler.
- Passing values between parent and child — Inputs/signals.
- Anything where the operator chain is longer than the feature it implements.

**Always unsubscribe.** `takeUntilDestroyed()` (Angular 16+) is the modern pattern:

```ts
constructor() {
  this.service.stream$.pipe(takeUntilDestroyed()).subscribe(...);
}
```

`takeUntilDestroyed()` requires injection context (constructor or `inject()` scope). Or use `async` pipe in the template and avoid manual subscriptions entirely — best option when it fits.

## Dependency injection

- **`inject()` function** for DI in most cases, incl. non-class contexts.
- Constructor DI still works and is fine; pick one style per codebase.
- `providedIn: 'root'` for singletons; omit `providedIn` for component-scoped services.
- **Don't `new` services.** Services come from the injector. Testing the component means overriding the provider, not mocking `new`.

## Forms

- **Reactive Forms** over Template-Driven for anything non-trivial.
- `FormBuilder` or `formGroup` literals; typed forms (Angular 14+) with `FormControl<string>`.
- Custom validators return `null` or `{ errorKey: payload }`.
- Form errors bound in the template: `@if (form.get('email')?.errors?.['required']) { ... }`.
- **Disable while submitting**; prevent double-submit.

Template-driven forms are fine for "two inputs and a submit." Anything with cross-field validation or dynamic controls: reactive.

## Routing

- **Lazy-load feature routes.** `loadComponent: () => import(...)` for standalone components; `loadChildren: () => import(...)` for grouped routes.
- **Route-level guards** as functions (`CanActivateFn`), not classes. The old class-based guards are deprecated.
- **Resolvers** for pre-loading route data so the component renders with data ready; alternative: component fetches in constructor/ngOnInit.
- **`provideRouter(routes, withComponentInputBinding())`** — route params flow as `@Input()` automatically.

## HTTP

- **`HttpClient`** with typed response: `http.get<User>('/api/user')`.
- **Interceptors as functions** (`HttpInterceptorFn`), not class interceptors. Register with `provideHttpClient(withInterceptors([...]))`.
- **Retries and timeouts explicit.** `retry({ count: 2, delay: 300 })`, `timeout(5000)`.
- **Cancel on unmount** via `takeUntilDestroyed()` or `async` pipe.

## Performance

- `OnPush` change detection everywhere — already mentioned, important enough to repeat.
- `trackBy` / `track` on every list.
- **Lazy load feature routes + standalone components.** Don't ship the whole app on the login page.
- **Signals over RxJS** for component reactivity reduces change-detection cost.
- **Deferred loading**: `@defer { ... } @placeholder { ... } @loading { ... }` for below-the-fold or conditional heavy pieces.
- **`@Pipe({ pure: true })`** (default) — impure pipes rerun every CD cycle, huge cost multiplier.

## Testing

- **Unit**: Karma + Jasmine is default; **Jest** or **Vitest** is increasingly popular and faster.
- **Component tests**: prefer testing behavior via `TestBed` + signals/DOM inspection over testing implementation (the exact order of method calls).
- **E2E**: Cypress or Playwright. Protractor is dead.
- Mock `HttpClient` with `HttpClientTestingModule`; flush expected requests explicitly so missing requests fail loudly.

## Styling

- **Component-scoped styles via `styleUrls` / `styles`** with Angular's view encapsulation (default: Emulated). `::ng-deep` is deprecated — use CSS custom properties instead.
- **Tailwind** works well with Angular; configure PurgeCSS to scan `.html` and `.ts` templates.
- **Angular Material** for off-the-shelf UI; **PrimeNG** as an alternative with richer component library.

## Do not

- Do not use `any` — Angular's typed forms, typed HttpClient, and typed signals make this unnecessary.
- Do not use `NgModule` for new code unless forced by a library.
- Do not subscribe without `takeUntilDestroyed()`, `async` pipe, or explicit teardown.
- Do not mutate `@Input()` values inside a component — treat inputs as read-only.
- Do not use `*ngIf="user$ | async; else loading"` for complex branching — the new `@if` control flow is cleaner.
- Do not perform heavy work in `ngOnChanges` — it runs on every input change; prefer `computed()` signals.
- Do not manipulate the DOM directly. Use Angular's `Renderer2` or template bindings.
