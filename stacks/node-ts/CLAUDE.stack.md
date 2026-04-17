<!-- source: stacks/node-ts -->

# Node / TypeScript conventions

This stack layer applies to any Node.js or browser project using
TypeScript (or modern JavaScript). Framework-specific rules (React,
Angular, Next.js) live in their own stack layers and refine these.

## Runtime & tooling

- **Package manager:** respect the project's lockfile.
  - `pnpm-lock.yaml` → pnpm
  - `yarn.lock` → yarn
  - `package-lock.json` → npm
  - `bun.lock` / `bun.lockb` → bun
  Never switch package managers without explicit instruction. Installing with the wrong one rewrites the lockfile and spawns "why did 400 files change" reviews.
- **Node version** is pinned via `.nvmrc`, `.node-version`, or `package.json#engines`. Treat that as authoritative.
- **TypeScript `strict: true`** is the default expectation. If the project has it off, treat that as technical debt, not license to opt out in new files.
- **Target** ES2022+ for Node 18+, ES2020+ for older runtimes. Check `tsconfig.json`.

## Module system

- **ESM vs CommonJS** — check `"type": "module"` in `package.json`.
  - ESM: use `import`/`export`, `.js` extensions in relative imports (yes, even for `.ts` source — TS compiles-through the `.js` suffix), top-level `await` works.
  - CJS: use `require`/`module.exports`; `__dirname` available directly.
  Mixing is painful. Don't introduce CJS into an ESM project or vice versa without a clear reason.
- Prefer **named exports** over default exports. Default exports break tree-shaking guarantees and make renaming during refactor harder.

## TypeScript idioms

- **`unknown` over `any`.** `any` is a code smell; `unknown` forces a type check at the use site.
- **Discriminated unions** for state: `{ status: "loading" } | { status: "ok"; data: T } | { status: "error"; error: E }`. Enforces exhaustive handling.
- **`type` for unions/intersections/functional shapes; `interface` for object shapes you may want to extend/merge.** Either is fine; be consistent within a module.
- **`readonly` where data shouldn't mutate.** `readonly T[]` and `ReadonlyMap` save debugging time.
- **Avoid type assertions** (`as Foo`) except at genuine boundary points (JSON parse, third-party API response). They silence the compiler without adding safety.
- **No `!` non-null assertions** in new code. If you're asserting non-null, the type model is wrong somewhere.

## Async

- **Everything I/O is async.** Callbacks are legacy; use promises / async-await.
- **`await` every promise** — or explicitly `.catch(...)`. Unhandled rejections crash Node 15+.
- **`Promise.all` for parallel**; `Promise.allSettled` when you want every outcome; `for await ... of` for streaming sequentially.
- **Timeouts:** `AbortController` + `AbortSignal.timeout(ms)` for `fetch` and any API that accepts a signal. No timeout = hung requests.

## Error handling

- **Throw `Error` subclasses**, not strings. Errors should carry `name` and `message`; ideally a `cause` (via `new Error(msg, { cause: original })`) when translating.
- **Narrow catches** — `catch (e)` + `instanceof` checks. Top-level `try/catch` that swallows everything is a bug.
- **No `catch (e) {}`**, ever. If the error is ignorable, log it and say why.

## Logging

- Use a real logger (`pino`, `winston`) in services — not `console.log`. `console.log` in a service loses structure and is slow.
- In libraries, don't log at all; return errors or expose events. Let the caller decide.

## Testing

- **Vitest** for new projects; **Jest** for legacy. They share most of their API.
- **Co-locate tests** (`foo.ts` + `foo.test.ts`) unless the project already has a `tests/` tree.
- **No snapshot tests of rendered HTML walls.** They're diff-reviewed as "looks okay" and change-blind. Snapshots of parsed ASTs, API responses, or narrow component output are fine.
- **Mock at the boundary** — fetch, DB, filesystem. Don't mock your own code.

## Lint & format

- **ESLint + @typescript-eslint** for semantics, **Prettier** for formatting — different jobs, don't make them fight.
- Format is a hook concern (see `hooks/format-prettier.sh`), not a review concern. Don't nitpick formatting.

## Builds

- **Server code:** typically `tsc` or `tsx`/`ts-node` for scripts. Build artifact goes to `dist/` and is gitignored.
- **Library:** publish both `dist/esm` and `dist/cjs` if you want broad compatibility; use `package.json#exports` with `import`/`require` conditions.
- **Frontend:** framework-specific (see `stacks/react`, `stacks/angular`).

## Environment

- **No `dotenv` in production-loaded code paths.** Read from `process.env` directly; the runtime (systemd, Docker, K8s, Vercel) is responsible for injecting env.
- **Validate env at boot** — use `zod` or similar. A missing required env var should crash at startup, not trigger a mysterious 500 three hours later.

## What NOT to reach for

- **No `require` in an ESM project.** Use dynamic `import()`.
- **No `var`.** `const` by default, `let` when you must reassign.
- **No `==`.** `===`.
- **No `.forEach` when you need async**; it doesn't await.
- **No lodash** for things the stdlib does now (`Array.prototype.flatMap`, `structuredClone`, `Object.fromEntries`). Dep audit.
