# Runtime validation: zod, valibot, arktype

TypeScript types are *erased* at runtime. A `User` type means nothing once
the JSON has been `JSON.parse`'d. Every trust boundary needs a runtime
validator.

## When you need a validator

- Parsing JSON from HTTP, message queues, files, or DBs typed as `jsonb`.
- Reading `process.env` (everything is `string | undefined` — validate
  shape and coerce).
- Accepting form data in API route handlers.
- Anywhere the source of a value is not TypeScript code you control.

## Pick one

| Library | Bundle | Strength |
|---|---|---|
| [zod](https://zod.dev) | ~13 KB gz | Most ecosystem support (trpc, React Hook Form, tanstack) |
| [valibot](https://valibot.dev) | ~1–5 KB gz (tree-shaken) | Smallest runtime; great for edge / client bundles |
| [arktype](https://arktype.io) | ~5 KB gz | Syntax close to TS literal types; fast |

Pick zod by default. Pick valibot if bundle size dominates (edge
runtimes, public-facing client apps). Pick arktype if your team likes its
syntax and is okay being on the leading edge.

## zod essentials

```ts
import { z } from 'zod';

export const UserSchema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
  age: z.number().int().min(0).max(150),
  role: z.enum(['admin', 'member', 'guest']),
  createdAt: z.coerce.date(),
  tags: z.array(z.string()).default([]),
});

export type User = z.infer<typeof UserSchema>;

// Parse — throws ZodError on failure (good for server code)
const user = UserSchema.parse(rawJSON);

// Safe parse — discriminated result (good for boundary code)
const result = UserSchema.safeParse(rawJSON);
if (!result.success) {
  return { error: result.error.flatten() };
}
const user2 = result.data;
```

The schema is the single source of truth: the type is inferred from it,
never written separately.

## Environment variables

```ts
import { z } from 'zod';

const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().default(3000),
  DATABASE_URL: z.string().url(),
  SECRET_KEY: z.string().min(32),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
});

export const env = EnvSchema.parse(process.env);
// env.PORT is number, not string — z.coerce.number handled that
```

Fail fast at boot — crash rather than start with a malformed env.

## Discriminated unions

```ts
const Event = z.discriminatedUnion('kind', [
  z.object({ kind: z.literal('click'), x: z.number(), y: z.number() }),
  z.object({ kind: z.literal('key'),   code: z.string() }),
  z.object({ kind: z.literal('focus'), target: z.string() }),
]);

type Event = z.infer<typeof Event>;
```

`discriminatedUnion` is faster and produces better error messages than
`union`.

## Transformations

Parse *and* transform in one step:

```ts
const DateFromISO = z.string().datetime().transform((s) => new Date(s));

const LogEntry = z.object({
  timestamp: DateFromISO,
  level: z.string().toLowerCase(),
  message: z.string().trim(),
});
```

The inferred type reflects the transformed value (`Date`, not `string`).

## Custom refinements

```ts
const Password = z.string()
  .min(12)
  .regex(/[A-Z]/, 'must contain uppercase')
  .regex(/[a-z]/, 'must contain lowercase')
  .regex(/\d/,    'must contain digit');

const Form = z.object({
  password: Password,
  confirm:  Password,
}).refine(
  (data) => data.password === data.confirm,
  { message: 'Passwords must match', path: ['confirm'] },
);
```

## Parse, don't validate

After parsing, operate on the validated type — don't keep passing the raw
input around and re-validating. This is the core idea behind Alexis King's
"parse, don't validate": push validation to the edge once, then everything
downstream gets strong types for free.

```ts
// ❌ reactive validation everywhere
function chargeUser(user: unknown) {
  if (!isValidUser(user)) throw new Error('bad');
  // ...
}

// ✅ parse once, operate on the strong type
function chargeUser(user: User) { /* ... */ }

// Call site:
const user = UserSchema.parse(payload);
chargeUser(user);
```

## API integration

- **tRPC**: schemas double as input validators and client-side types.
- **Next.js App Router**: use `z.safeParse` inside Server Actions / route
  handlers to produce `{ error }` / `{ data }` shapes.
- **React Hook Form**: use `@hookform/resolvers/zod` for form validation;
  submit types inferred.
- **Express / Fastify**: wrap handlers in a tiny helper that parses
  `req.body` with the schema and passes typed input downstream.

## Performance notes

- Zod parse cost is real at high QPS. For hot paths (10k+ rps), benchmark
  against valibot.
- Precompile schemas — don't rebuild them per request. Import and reuse.
- For large payloads, use `.passthrough()` / `.strip()` deliberately — don't
  let unvalidated keys leak through your type.

## Errors and user-facing messages

`error.flatten()` gives per-field errors suitable for form UIs:

```ts
{
  formErrors: [],
  fieldErrors: {
    email: ['Invalid email'],
    age:   ['Must be at least 0'],
  }
}
```

For logging / machine consumption, use `error.issues` — structured per-issue
detail with `path`, `code`, `message`.

## Don't double-validate

If your HTTP framework already validates with the same schema (e.g., tRPC),
don't re-parse inside the handler. Once parsed, stay parsed.
