# Advanced TypeScript types

The type-system tools that cover the "I need the compiler to understand
this shape" cases.

## Conditional types

```ts
type IsArray<T> = T extends readonly unknown[] ? true : false;

type A = IsArray<number[]>;   // true
type B = IsArray<string>;     // false
```

Distribute over unions (this is how `NonNullable` works):

```ts
type NonNull<T> = T extends null | undefined ? never : T;
type X = NonNull<string | null | undefined>;  // string
```

Wrap in a tuple to prevent distribution when you don't want it:

```ts
type IsUnion<T, U = T> = T extends unknown ? ([U] extends [T] ? false : true) : never;
```

## Mapped types

```ts
type Readonly<T> = { readonly [K in keyof T]: T[K] };
type Partial<T>  = { [K in keyof T]?: T[K] };
type Required<T> = { [K in keyof T]-?: T[K] };   // strip optionality
```

With key remapping (4.1+):

```ts
type Getters<T> = {
  [K in keyof T as `get${Capitalize<string & K>}`]: () => T[K];
};

type UserGetters = Getters<{ name: string; age: number }>;
// { getName: () => string; getAge: () => number }
```

## Template literal types

Pattern-match strings:

```ts
type EventName = `on${Capitalize<'click' | 'hover' | 'focus'>}`;
// "onClick" | "onHover" | "onFocus"

type Route = `/users/${string}` | `/posts/${number}/comments`;
```

Extract params:

```ts
type Params<S extends string> =
  S extends `${string}:${infer P}/${infer Rest}`
    ? P | Params<`/${Rest}`>
    : S extends `${string}:${infer P}`
      ? P
      : never;

type Users = Params<'/users/:userId/posts/:postId'>;   // "userId" | "postId"
```

## `infer`

Extract parts of a type inside a conditional:

```ts
type ReturnType<F> = F extends (...a: any[]) => infer R ? R : never;
type First<T>      = T extends readonly [infer H, ...unknown[]] ? H : never;
type Last<T>       = T extends readonly [...unknown[], infer L] ? L : never;
type Awaited<T>    = T extends Promise<infer U> ? Awaited<U> : T;
```

## Built-in utility types

| Utility | What it does |
|---|---|
| `Partial<T>` | All fields optional |
| `Required<T>` | All fields required |
| `Readonly<T>` | All fields readonly |
| `Pick<T, K>` | Keep listed keys |
| `Omit<T, K>` | Drop listed keys |
| `Record<K, V>` | Dictionary type |
| `Exclude<T, U>` | `T` minus members assignable to `U` |
| `Extract<T, U>` | `T` intersected with members assignable to `U` |
| `NonNullable<T>` | `T` without `null \| undefined` |
| `Parameters<F>` | Tuple of `F`'s parameters |
| `ReturnType<F>` | Return type of `F` |
| `Awaited<T>` | Unwrap Promises recursively |
| `NoInfer<T>` | (5.4+) Don't infer `T` from this position |
| `ConstructorParameters<C>` | Tuple of class ctor params |
| `InstanceType<C>` | Class instance type |

## Discriminated unions + exhaustiveness

The single most useful runtime-safe pattern.

```ts
type Result<T> =
  | { status: 'ok'; data: T }
  | { status: 'error'; message: string }
  | { status: 'loading' };

function describe<T>(r: Result<T>): string {
  switch (r.status) {
    case 'ok':      return `got ${JSON.stringify(r.data)}`;
    case 'error':   return `fail: ${r.message}`;
    case 'loading': return 'loading…';
    default:        return assertNever(r);
  }
}

function assertNever(x: never): never {
  throw new Error(`Unhandled: ${JSON.stringify(x)}`);
}
```

`assertNever` makes adding a new variant a *compile error* until every
switch handles it. Use this pattern everywhere.

## Branded types for domain safety

TypeScript is structural — `UserId` and `PostId` are both `string`, so
they're interchangeable. Brand them:

```ts
type Brand<T, B> = T & { readonly __brand: B };

type UserId = Brand<string, 'UserId'>;
type PostId = Brand<string, 'PostId'>;

const asUserId = (s: string): UserId => s as UserId;

declare function loadUser(id: UserId): User;
declare const raw: string;
loadUser(raw);              // ERROR — raw isn't a UserId
loadUser(asUserId(raw));    // OK
```

Great for IDs, validated inputs (`Email`, `URL`), unsafe strings (`SQL`,
`HTML`).

## `NoInfer<T>` (5.4+)

Prevent TS from inferring `T` from a specific parameter position:

```ts
declare function pick<T>(options: T[], fallback: NoInfer<T>): T;

pick(['a', 'b'], 'c');     // error — 'c' is not in the options
```

Before `NoInfer`, TS would widen to `'a' | 'b' | 'c'` and accept.

## `satisfies` vs. `as`

`satisfies` checks without widening. Use for config-like constants where you
want inference on literal members:

```ts
const config = {
  port: 3000,
  env: 'production',
} satisfies { port: number; env: 'production' | 'development' };

config.env;     // inferred as 'production', not the whole union
```

`as` forces a type — it silences the compiler. Reserve `as` for clearly-safe
narrowings (usually after a zod parse).

## Recursive types

```ts
type JSONValue =
  | string
  | number
  | boolean
  | null
  | JSONValue[]
  | { [k: string]: JSONValue };
```

Recursion depth limit is 1000 by default. If you hit it, redesign — you
probably shouldn't be computing that much at the type level.

## Type-level tests

```ts
type Expect<T extends true> = T;
type Equal<X, Y> =
  (<T>() => T extends X ? 1 : 2) extends
  (<T>() => T extends Y ? 1 : 2) ? true : false;

type tests = [
  Expect<Equal<ReturnType<() => number>, number>>,
  Expect<Equal<Parameters<(a: string, b: boolean) => void>, [string, boolean]>>,
];
```

Put these in a `*.test-d.ts` file and run `tsc --noEmit` in CI.

## Where the type system runs out

Use a runtime validator (zod, valibot, arktype) when:

- Parsing JSON from the network, from disk, from env vars.
- Boundaries with untyped code (any `any`, any dynamic `require`).
- You want a single source of truth for shape *and* validation.

Use zod's `z.infer<typeof Schema>` as your TS type.
