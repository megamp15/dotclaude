# Generics and inference

When to reach for generics vs. overloads vs. unions, and how to make inference
work for callers.

## The "do I need a generic?" test

Generics are warranted when **the return type depends on the input type**:

```ts
// ✅ generic — return mirrors input
function first<T>(xs: readonly T[]): T | undefined { return xs[0]; }

// ❌ not a generic — return is always string
function toString<T>(x: T): string { return String(x); }    // just: (x: unknown) => string
```

## Constraints

Constrain what `T` can be:

```ts
function hasId<T extends { id: string }>(x: T): string { return x.id; }

hasId({ id: '1', name: 'a' });    // T = { id: string; name: string }
hasId({ name: 'a' });             // error
```

## Defaults

Generic defaults unblock optional type parameters:

```ts
interface Result<Data, Err = Error> {
  ok: boolean;
  data?: Data;
  error?: Err;
}

const r: Result<User> = { ok: true, data: someUser };
```

## Variance, practically

You rarely need to think about `in`/`out` annotations unless you're writing
library-style code. The rule of thumb:

- **Parameter positions** are contravariant — a function that accepts `Animal`
  is assignable to something expecting a function that accepts `Dog`.
- **Return positions** are covariant.

If you're fighting the compiler, swap a generic for a union or vice versa —
it's usually a sign of the wrong shape.

## Inference from callback arguments

Library authors get this wrong all the time.

```ts
// ❌ T is inferred from the wrong place
declare function map<T, U>(xs: T[], fn: (x: T, i: number) => U): U[];

// The call:
map([1, 2], n => String(n));
// T is correctly inferred as number, U as string ✓
// But T gets inferred from `xs`. If someone writes:
map<string>([1, 2], n => n.toUpperCase());    // type arg shouldn't really exist here
```

Use `NoInfer` (5.4+) to control which position drives inference:

```ts
declare function map<T, U>(
  xs: T[],
  fn: (x: NoInfer<T>, i: number) => U,
): U[];
```

Now `T` is inferred from `xs` only.

## Overloads vs. generics

Use **overloads** when signatures differ by shape, not by a type parameter:

```ts
function parse(s: string): number;
function parse(s: string, base: number): string;
function parse(s: string, base?: number): number | string {
  return base === undefined ? Number(s) : parseInt(s, base).toString(base);
}
```

Use a **generic** when there's one signature whose type flows through:

```ts
function identity<T>(x: T): T { return x; }
```

Overload order: most specific first. The implementation signature must
accept every overload signature as a valid call.

## `as const`

Freeze literal inference:

```ts
const roles = ['admin', 'member', 'guest'] as const;
type Role = typeof roles[number];       // 'admin' | 'member' | 'guest'

const config = { port: 3000 } as const; // { readonly port: 3000 }
```

Use for: enum-like string lists, config constants, tuple literals.

Don't use for: objects whose fields will be mutated.

## `satisfies` for config objects

```ts
type Config = {
  port: number;
  env: 'dev' | 'prod';
};

// ❌ `as Config` loses the literal
const bad = { port: 3000, env: 'dev' } as Config;
// bad.env is 'dev' | 'prod', not 'dev'

// ✅ `satisfies` validates and keeps the literal
const good = { port: 3000, env: 'dev' } satisfies Config;
good.env;   // 'dev'
```

## Generic constraints that reference other generics

```ts
function get<T, K extends keyof T>(obj: T, key: K): T[K] {
  return obj[key];
}

const u = { id: 1, name: 'a' };
const n = get(u, 'name');    // string, inferred
const x = get(u, 'oops');    // error — not a key
```

## `infer` inside conditional types (power move)

```ts
type AsyncReturn<F> = F extends (...args: any[]) => Promise<infer R> ? R : never;

type R = AsyncReturn<() => Promise<User>>;     // User
```

## Higher-kinded workarounds

TS has no HKT support. Two workarounds:

- **Function wrappers**: pass a factory `<T>() => Thing<T>` instead of a
  `Thing<_>`.
- **Indexed record of constructors**: map string keys to concrete types.

If you're reaching for HKTs, reconsider the design — TS is not Haskell.

## Common inference failures and fixes

| Symptom | Cause | Fix |
|---|---|---|
| Inferred too wide (`string` instead of `'a'`) | TS widens literals | `as const` or `satisfies` |
| Inferred as `unknown` | No type source | Add an annotation on the binding |
| Inferred as union of all options | Generic not constrained | `extends keyof T` / literal constraint |
| Works standalone, breaks in a generic call | Parameter position doesn't allow distribution | Wrap arg in `[T]` or invert the generic |
| `never` in return | Discriminant ran out of cases | You probably want `assertNever`; the code path is reachable but TS thinks not |

## When to stop pushing the type system

If the type-level code is:

- Harder to read than the runtime code it describes,
- More than ~20 lines for a single helper,
- Relying on "clever" recursion to avoid a small union,

…it's probably time to accept a looser type and compensate with runtime
checks. The type system is a tool, not a trophy case.
