---
name: typescript-pro
description: Deep TypeScript 5+ expertise — generics (constraints, defaults, inference), conditional / mapped / template-literal types, discriminated unions with `never` exhaustiveness, branded types, `satisfies`, module shape (ESM vs CJS, `exports` map), and the pragmatic limits of the type system. Extends the rules in `stacks/node-ts/CLAUDE.stack.md`.
source: stacks/node-ts
triggers: /typescript-pro, advanced typescript, ts generics, conditional types, mapped types, template literal types, discriminated union, branded types, satisfies operator, tsconfig strict, exports map, ESM vs CJS, declaration files, d.ts, zod vs typescript
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/typescript-pro
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# typescript-pro

Production-grade TypeScript 5+ expertise for people already past `strict: true`.
Activates when the question is about the type system itself — inference, design,
or "why doesn't this narrow".

> **See also:**
>
> - `stacks/node-ts/CLAUDE.stack.md` — baseline conventions
> - `stacks/node-ts/rules/ts-style.md` — enforceable rules
> - `stacks/react/skills/react-expert/` — if the question is React-shaped
> - `stacks/nextjs/skills/nextjs-developer/` — if Next.js App Router
> - `core/skills/code-documenter/references/typescript-jsdoc.md` — JSDoc conventions

## When to use this skill

- Designing a library-level API that should infer well for callers.
- Debugging "why doesn't this discriminate" / "why is this `any`".
- Replacing runtime validation with types where safe; admitting where zod is
  required.
- Shipping a package that works for ESM *and* CJS consumers.
- Writing `.d.ts` for an untyped dep without shipping noise.

## References (load on demand)

- [`references/advanced-types.md`](references/advanced-types.md) — conditional,
  mapped, template-literal, recursive types. Inference helpers (`Parameters`,
  `ReturnType`, `Awaited`, `NoInfer`).
- [`references/generics-and-inference.md`](references/generics-and-inference.md)
  — when to use generics vs. unions vs. overloads; constraints, defaults,
  `satisfies`, `as const`, and how inference flows.
- [`references/modules-and-packaging.md`](references/modules-and-packaging.md)
  — `tsconfig`, ESM / CJS dual publish, `exports` map, `.d.ts` authoring,
  `moduleResolution: "Bundler"` vs `"NodeNext"`.
- [`references/runtime-validation.md`](references/runtime-validation.md) —
  zod / valibot / arktype, inferring types from schemas, the "parse, don't
  validate" rule, type-first vs. schema-first design.

## Core workflow

1. **Pin the tsconfig** — most "TS is weird" issues are actually "your tsconfig
   is permissive". Verify `strict`, `noUncheckedIndexedAccess`,
   `exactOptionalPropertyTypes`.
2. **Minimize the reproducer** — paste the failing snippet into the TS
   Playground with the exact `tsconfig`. If it works there, the issue is
   project-local (module resolution, global types, lib).
3. **Ask what you want inference to do** — forward from caller? infer from
   return? discriminate on a literal? That dictates generics vs. overloads
   vs. conditional types.
4. **Avoid runtime drift** — types without runtime validation at trust
   boundaries are a bug waiting to happen. Use zod/valibot/arktype.
5. **Ship correctly** — dual publish ESM + CJS with `exports` map; don't rely
   on consumer-side interop hacks.

## Defaults

| Question | Default |
|---|---|
| "Does this value match this shape at runtime?" | zod / valibot — not TS alone |
| Union with a discriminant | tagged union on a `Literal` string; exhaustive `switch` with `never` default |
| "I want inference, not rigidity" | `satisfies` on config/constants, `as const` for literal arrays |
| Library exposing a callback | Generic function; `NoInfer<T>` for slots you want callers to pass explicitly |
| Package shape | ESM-first, dual-published; `type: "module"` in package.json; named exports only |
| Types for an untyped dep | Local `src/types/<pkg>.d.ts` with `declare module`; open-source it later |
| "Runtime shape matches TypeScript shape" | zod's `z.infer` as the type source of truth |
| Error type | Subclass `Error` with a `code: "..."` discriminant |

## Anti-patterns

- **`any`** — ban at lint level (`@typescript-eslint/no-explicit-any`). Use
  `unknown` for "I'll narrow later".
- **Type assertions (`as X`) as narrowing** — use `is` type predicates or a
  schema. `as` silences the compiler instead of convincing it.
- **Non-null assertion (`x!`) in app code** — acceptable in tests; in prod it's
  almost always a sign the type is wrong.
- **`enum`** — use `as const` objects or string literal unions. `enum` emits
  runtime code and doesn't tree-shake.
- **Mixing default and named exports** — pick named. Default exports break
  auto-import and rename-refactors.
- **Runtime `instanceof` across bundles** — classes from two copies of a lib
  fail `instanceof`. Tag with a `kind` literal instead.
- **`tsc` as a bundler** — `tsc` emits, bundlers bundle. Use `tsup`, `unbuild`,
  or the framework's bundler.

## Output format

For type-design questions:

```
Signature:
  <the type>

Inferred call site:
  <what caller sees>

Breaks if:
  <variance / narrowing limit>

Alternative:
  <the less-elegant but clearer fallback>
```

For packaging:

```
package.json:
  <the exports map, type, main, module fields>

Build output:
  <what tsup/unbuild produces>

Consumer import:
  <how it looks in both ESM and CJS>
```
