# Modules and packaging

Shipping a TypeScript package that works for ESM *and* CJS consumers without
weird runtime failures.

## `tsconfig.json` starting point

For application code:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "lib": ["ES2022", "DOM"],
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitOverride": true,
    "noFallthroughCasesInSwitch": true,
    "isolatedModules": true,
    "verbatimModuleSyntax": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "resolveJsonModule": true
  }
}
```

For a library you're publishing, use `"moduleResolution": "NodeNext"` and
`"module": "NodeNext"` to match how Node will resolve your output.

Key strict flags worth the pain:

- `strict: true` — the omnibus.
- `noUncheckedIndexedAccess: true` — `arr[0]` is `T | undefined`, as it
  should be.
- `exactOptionalPropertyTypes: true` — `x?: string` doesn't silently accept
  `undefined`; you have to write `x?: string | undefined` if you mean it.
- `verbatimModuleSyntax: true` — enforces `import type { … }` for
  type-only imports, which lets bundlers erase them cleanly.

## ESM vs CJS, 2026 edition

- New code: ESM. `"type": "module"` in `package.json`.
- Publishing a library: **dual publish** ESM + CJS so consumers of both work.
- Use a bundler (`tsup`, `unbuild`, `tshy`) — don't hand-write two builds.

## `exports` map for dual publishing

```json
{
  "name": "my-lib",
  "version": "1.0.0",
  "type": "module",
  "main": "./dist/index.cjs",
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js",
      "require": "./dist/index.cjs"
    },
    "./utils": {
      "types": "./dist/utils.d.ts",
      "import": "./dist/utils.js",
      "require": "./dist/utils.cjs"
    },
    "./package.json": "./package.json"
  },
  "files": ["dist"],
  "sideEffects": false
}
```

Rules:

- `types` must come **first** in each conditions block — TS reads in order.
- `sideEffects: false` unlocks tree-shaking if your code really has none.
  Put `["./dist/side.js"]` if specific files have side effects.
- Export `./package.json` explicitly — tools like Vite look it up.
- Don't ship TS source unless you really mean to — ship compiled JS + `.d.ts`.

## Build with `tsup`

```ts
// tsup.config.ts
import { defineConfig } from 'tsup';

export default defineConfig({
  entry: ['src/index.ts', 'src/utils.ts'],
  format: ['esm', 'cjs'],
  dts: true,
  sourcemap: true,
  clean: true,
  target: 'es2022',
  treeshake: true,
});
```

```bash
tsup
# produces dist/index.{js,cjs,d.ts} and dist/utils.{js,cjs,d.ts}
```

## Declaration files for untyped deps

When a dep has no types and no `@types/<pkg>`:

```
src/
  types/
    legacy-thing.d.ts
```

```ts
// src/types/legacy-thing.d.ts
declare module 'legacy-thing' {
  export interface Options { timeout?: number; }
  export function run(opts?: Options): Promise<void>;
}
```

Include the folder in `tsconfig.json`:

```json
{
  "include": ["src/**/*.ts", "src/types/**/*.d.ts"]
}
```

Open-source the types later if the project will accept a PR — that's how the
`@types/*` ecosystem gets better.

## `verbatimModuleSyntax` and `import type`

```ts
import type { User } from './user';      // erased at build time
import { fetchUser } from './user';      // remains

export type { User };
export { fetchUser };
```

Runtime imports must be present in the output. Type-only imports must be
marked. This makes bundlers happier and prevents "why is this file loaded
for just types".

## Paths / aliases

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@app/*": ["src/*"],
      "@shared/*": ["packages/shared/src/*"]
    }
  }
}
```

TS understands aliases, but **Node and bundlers don't by default**. Match
them in your runtime:

- Vite / Rollup / webpack: config aliases.
- Node directly: `tsx` or `tsconfig-paths` — or bake the resolution into
  your build output.

Libraries shouldn't use `paths` in shipped code — consumers won't resolve
them.

## Monorepo shape

- Prefer `pnpm` + workspace protocol.
- Each package is self-contained: its own `tsconfig.json`, its own
  `package.json`, its own `dist/`.
- Use `tsconfig.base.json` + `extends` in each package.
- TypeScript **project references** (`"composite": true`) speed up `tsc`
  across packages if you use `tsc` to build. Bundlers make this less
  essential.

## Runtime entry sniffing

Know the difference between:

- `"main"` — CJS entry (`require('my-lib')`)
- `"module"` — ESM entry (legacy bundler hint)
- `"exports"` — the authoritative map for modern resolvers
- `"types"` — top-level types fallback (covered per-condition inside
  `exports.types`)

When in doubt, run `npm publish --dry-run` and inspect the tarball —
`node-v18-dts-check` tools show what consumers see.

## Version ranges

- Libraries: `"peerDependencies": { "zod": "^3.22" }`. Let consumers own
  the runtime copy.
- Apps: pin tightly; commit the lockfile.

## Publishing checklist

- `publint dist/` — catches `exports` map mistakes.
- `@arethetypeswrong/cli` (`attw`) — catches dual-publish type
  misconfiguration.
- `changeset version && changeset publish` for versioning, or `semantic-release`.
- `LICENSE` file present.
- `README.md` starts with the installation command and a 10-line usage
  example.
