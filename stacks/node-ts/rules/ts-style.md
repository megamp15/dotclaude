---
name: typescript-style
description: TypeScript-specific style and idioms. Refines core/rules/code-quality.md.
source: stacks/node-ts
alwaysApply: true
globs: ["**/*.ts", "**/*.tsx", "**/*.mts", "**/*.cts"]
---

# TypeScript style

Refines core rules with TS specifics. Don't repeat core here; only
language-idiomatic guidance.

## Types

- **Let inference do the work.** Don't re-annotate when TS already knows: `const n = 1` needs no `: number`. Annotate **public API boundaries** (exported functions, class methods) and **catch-points** (argument destructuring, callback params) where inference is weak.
- **Widen only when necessary.** `as const` for literal arrays and object shapes that should stay narrow. Avoid accidental `string` where `"foo" | "bar"` was meant.
- **Use `satisfies`** (TS 4.9+) instead of `as` when you want to validate a value matches a type without losing the narrower inferred type: `const config = { mode: "dev" } satisfies Config`.

## Type narrowing

- Prefer **user-defined type guards** (`x is Foo`) over casts.
- **`in` operator** for structural checks (`"data" in res`).
- **Exhaustiveness check** in discriminated unions via `never`:

```ts
function handle(s: State) {
  switch (s.kind) {
    case "loading": return ...;
    case "ok": return ...;
    case "error": return ...;
    default: {
      const _exhaustive: never = s;
      throw new Error(`unhandled state: ${_exhaustive}`);
    }
  }
}
```

Adding a new state is a type error until you handle it.

## Avoid

- **`any`** — every `any` is technical debt. If you need an escape hatch, `unknown` + a guard, or a narrowly-scoped assertion at one call site.
- **`as Foo`** except at genuine boundaries (`JSON.parse`, third-party responses, decoded crypto). Even then: validate first (zod, io-ts, valibot), assert the validated type.
- **`!` non-null** in new code. If `x!.foo` feels right, the type or the control flow is wrong.
- **`Function`** as a type. Specify the signature.
- **`Object` / `{}`** as a type — they mean "anything except null/undefined," which is almost never what you mean. Use `unknown`, `Record<string, unknown>`, or a real type.
- **`enum`** for new code in most cases; prefer union-of-literals:
  ```ts
  type Role = "admin" | "user" | "guest";  // preferred
  ```
  String literal unions don't emit runtime code and are easier to serialize.

## Imports

- **Type-only imports:** `import type { Foo } from "./bar"`. Makes compile-away explicit; avoids circular import gotchas at runtime.
- **Absolute paths via `paths`** in `tsconfig.json` for deep trees; otherwise relative. Don't mix.
- **No default exports** except for genuine single-export modules (React components sometimes, rarely elsewhere). Named exports rename cleanly and compose with `import *`.

## Nullability

- **Model the absence explicitly.** `T | undefined` or `T | null` (pick one for the project and stick with it). Don't use sentinel values like `-1`, `""`, `0`.
- **Optional chaining** (`a?.b?.c`) and **nullish coalescing** (`a ?? default`) — use them. Don't write `a && a.b && a.b.c` anymore.
- Distinguish "missing" from "empty." `maybe: string | undefined` — a missing value is `undefined`; empty string is a different valid state.

## Async

- **Return `Promise<T>`, not `T | Promise<T>`.** If the function is async, type it that way consistently.
- **Reject with `Error` instances**, not strings, not objects. `reject(new Error("foo"))`, always.
- **`AsyncIterable` / generators** for streams; `Observable` only if the project already uses RxJS.

## Classes

- Prefer **functions + closures** to classes for most logic. Classes pay off for: React class components (legacy), ORM model base classes, DI containers, and genuinely stateful long-lived objects.
- **`readonly` on fields** by default in classes. Mutability must be justified.
- **`private` (TS keyword) vs `#field` (ECMAScript)** — `#` is true runtime-private; `private` is compile-time only. Prefer `#` for sensitive fields when on a modern target.

## React / JSX (if present; the `react` stack refines further)

- Prefer **function components**. Class components only if the project still has them.
- **Props as named interface or type** colocated in the same file.
- **`React.FC`** is optional and somewhat out of fashion — you can just annotate the props type.

## Utility types (use, don't re-invent)

- `Partial<T>`, `Required<T>`, `Pick<T, K>`, `Omit<T, K>`, `Record<K, V>`.
- `ReturnType<fn>`, `Parameters<fn>`, `Awaited<T>`.
- `NonNullable<T>`.

If you find yourself writing a helper type that already exists in lib.es5.d.ts, use the existing one.

## Linting

`@typescript-eslint` catches most of the above. Rules to keep on:

- `no-explicit-any`
- `no-unused-vars` (with `argsIgnorePattern: "^_"`)
- `no-non-null-assertion`
- `no-floating-promises`
- `no-misused-promises`
- `switch-exhaustiveness-check`

If they're off, understand why before adding new violations.
