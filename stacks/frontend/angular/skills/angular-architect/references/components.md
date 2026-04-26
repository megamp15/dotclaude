---
source: stacks/angular
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/angular-architect/references/components.md
ported-at: 2026-04-17
adapted: true
---

# Components, signals, input/output

## Standalone by default

```ts
@Component({
  selector: "app-user-list",
  standalone: true,
  imports: [CommonModule, RouterLink, UserCardComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  templateUrl: "./user-list.component.html",
  styleUrl: "./user-list.component.scss",
})
export class UserListComponent { /* … */ }
```

- No `NgModule`.
- `imports` lists only what the component uses.
- `OnPush` change detection.

## Inputs with `input()`

```ts
// required
user = input.required<User>();

// optional with default
pageSize = input<number>(20);

// with alias
externalId = input.required<string>({ alias: "id" });

// with transform
active = input<boolean, unknown>(false, { transform: booleanAttribute });
```

- `input()` returns a `Signal<T>`. Read with `this.user()`.
- `input.required<T>()` throws at runtime if the binding is missing.
- `transform` runs on every binding update — use for string → number
  or attribute → boolean coercion.

## Outputs with `output()`

```ts
selected = output<User>();
deleted = output<void>();

fire() {
  this.selected.emit(this.user());
  this.deleted.emit();
}
```

`output()` has no `EventEmitter` ceremony — it's a thin typed emitter.

## Two-way binding with `model()`

```ts
checked = model(false);
```

Template:

```html
<app-toggle [(checked)]="isEnabled()"></app-toggle>
```

`model()` creates an input + corresponding output (`checkedChange`) in
one call. Use for form-like components.

## Content + view queries as signals

```ts
headerRef = viewChild<ElementRef<HTMLElement>>("header");
items = viewChildren(ItemComponent);
projected = contentChildren(CardComponent);
```

`viewChild` / `viewChildren` / `contentChild` / `contentChildren` are
signal-based — react to them with `computed()` or `effect()`.

## Computed + effect

```ts
user = input.required<User>();
isAdmin = computed(() => this.user().role === "admin");
greeting = computed(() => `Hi, ${this.user().name}`);

constructor() {
  effect(() => {
    // runs when `user()` changes — side effects only
    this.analytics.track("user.viewed", { id: this.user().id });
  });
}
```

Rules:
- `computed()` is lazy + memoized — safe to call in templates repeatedly.
- `effect()` must be inside an injection context (component/directive
  constructor or `runInInjectionContext`).
- Don't set a signal inside a `computed()`. Don't do infinite-loopy
  things inside `effect()` either.

## Smart vs. dumb components

| Layer | Responsibility |
|---|---|
| Smart (routed) | Fetch data, own state, coordinate children |
| Dumb (leaf) | Pure render based on inputs; emit outputs |

- Dumb components have **no services**, no HTTP, no NgRx.
- Smart components inject services, read from the store, pass data down.

## Change detection

- `OnPush` everywhere. Inputs + signals + `async` pipe make this the
  right default.
- If you're fighting `OnPush`, you probably have mutable state. Switch
  to immutable updates (new object identity) or signals.

## Template control flow

```html
@if (user(); as u) {
  <app-user-card [user]="u" (selected)="pick($event)" />
} @else {
  <app-empty />
}

@for (item of items(); track item.id) {
  <app-row [item]="item" />
} @empty {
  <p>No items.</p>
}

@switch (mode()) {
  @case ("edit") { <app-edit /> }
  @case ("view") { <app-view /> }
  @default { <app-unknown /> }
}
```

- `@for` **requires** `track`. Use stable IDs.
- `@empty` clause replaces hand-rolled "if list empty" patterns.
- Old `*ngIf` / `*ngFor` still work but are deprecated for new code.

## Deferred views

```html
@defer (on viewport) {
  <app-comments />
} @placeholder {
  <app-skeleton />
} @loading (minimum 200ms) {
  <app-spinner />
}
```

Triggers: `on idle`, `on viewport`, `on interaction`, `on hover`, `on
immediate`, `on timer(Nms)`, `when <expr>`. Huge bundle wins for
below-the-fold features.

## Zoneless (preview)

`provideExperimentalZonelessChangeDetection()` drops Zone.js in favor
of signals-driven CD. Requires:
- All state backed by signals (no `setTimeout`/`Promise` change
  detection triggers).
- Third-party libs that cooperate (or adapters).

Worth experimenting with on new apps. Not something to migrate a big
codebase to casually.

## Anti-patterns

- Using `@Input()` / `@Output()` decorators in new components — use
  `input()` / `output()`.
- Reading signals outside a reactive context to drive side effects — use
  `effect()`.
- Stuffing business logic into dumb components (HTTP, NgRx, routing).
- `any` in signal types.
- Custom `trackBy` functions that return `$index` — you just disabled
  DOM reuse.
- `ViewEncapsulation.None` "just to make styles work" — prefer CSS
  custom properties.
