---
source: stacks/nextjs
---

# Stack: Next.js

Next.js 14+ App Router conventions. Layers on top of `core/`,
`stacks/node-ts`, and `stacks/react`. Read those first — this file
extends them, it doesn't replace.

## Version assumption

Target **Next.js 14+ with App Router**. This stack assumes:

- App Router (`app/` directory) — **never** Pages Router.
- React 19 features available (Server Components, Server Actions,
  `useActionState`, `useFormStatus`, `use()`).
- Turbopack for dev (`next dev --turbo` is the default).
- Node 20 LTS or later.

If the project is on the Pages Router or Next 12/13, migrate **then**
apply these rules. Don't retrofit App Router idioms into Pages code.

## Folder shape

```
app/
├── layout.tsx           # root layout
├── page.tsx             # home
├── loading.tsx          # root Suspense fallback
├── error.tsx            # root error boundary
├── not-found.tsx
├── globals.css
├── (marketing)/         # route groups — don't affect URL
│   └── about/page.tsx
├── products/
│   ├── layout.tsx
│   ├── page.tsx
│   ├── loading.tsx
│   ├── error.tsx
│   ├── [id]/
│   │   ├── page.tsx
│   │   └── generateMetadata
│   └── new/
│       └── page.tsx
├── api/                 # route handlers (preferred over pages API)
│   └── webhooks/route.ts
└── actions.ts           # server actions (or colocated)
```

Co-locate `loading.tsx`, `error.tsx`, and `not-found.tsx` with any
async route segment. Missing them is almost always a bug.

## Rendering strategy — pick intentionally

| Need | Choose |
|---|---|
| Mostly static, revalidates on schedule | **ISR** with `fetch(..., { next: { revalidate: N } })` |
| Fully static, rebuilds on deploy | **SSG** with `generateStaticParams` |
| Personalized per request | **SSR** with dynamic rendering (no-store or dynamic params) |
| Heavy interactivity | **Client Components** at the leaf |
| Most pages | **RSC + Suspense streaming** with ISR where possible |

Avoid "mark everything dynamic" — it throws away the whole reason to use
App Router. Measure, then choose.

## Data fetching

- Use native `fetch()` with explicit caching options. Never rely on
  implicit caching:

  ```ts
  await fetch(url, { cache: "force-cache" }); // default: cached
  await fetch(url, { cache: "no-store" });    // always fresh
  await fetch(url, { next: { revalidate: 60 } }); // ISR, 60s
  await fetch(url, { next: { tags: ["products"] } }); // on-demand
  ```

- For DBs, use your own client (Prisma, Drizzle, pg) inside Server
  Components. Don't import server-only modules into client code.
- Use `cache()` from `react` for request-scoped memoization inside
  Server Components.

## Server Actions

- Define with `"use server"`. One file at `app/actions.ts` or colocate
  with routes (`app/products/actions.ts`).
- Always re-validate: `revalidatePath("/products")` or
  `revalidateTag("products")`.
- Return typed results (don't just throw); clients may be progressive
  enhancement.
- Validate every input server-side (zod/valibot) — never trust form data.

## Client/server boundary

- Default to Server Components. Opt into client with `"use client"`
  only where needed (interactivity, browser APIs, stateful hooks).
- Don't `"use client"` a layout to unlock one widget — push the
  directive to the leaf.
- A Client Component may render Server Components **only as `children`
  props**, never via direct import.
- Server-only imports (`import "server-only"` at the top) for modules
  that must never reach the client bundle.

## Route handlers (`app/api/.../route.ts`)

Use route handlers for:
- Webhooks, third-party callbacks.
- Public REST endpoints consumed by mobile/external clients.
- Anything you'd put behind a public URL.

Do **not** use route handlers as a proxy for Server Actions when calling
from your own React. Server Actions are leaner and typesafe.

## Metadata + SEO

- Every route exports `metadata` (static) or `generateMetadata`
  (dynamic). No hand-written `<title>` / `<meta>` in JSX.
- Populate Open Graph + Twitter cards for shareable pages.
- Canonical URL set when duplication is possible.
- `robots`, `sitemap` via `app/robots.ts` / `app/sitemap.ts`.

## Images + fonts

- `next/image` for every content image. Never a bare `<img>` in a page.
- Provide `width`, `height`, and `alt`. Use `priority` for LCP images.
- `next/font` for all fonts — self-hosted by default, no CLS, no
  layout shift.

## Performance

- Code split at route level automatically; use `dynamic(() => import(...))`
  for heavy client-side components that render below the fold.
- Streaming: Suspense splits the page so above-the-fold ships first.
- Edge runtime where it helps (`export const runtime = "edge"`) — not
  by default; use when the handler is simple and latency-sensitive.
- Bundle check: `next build` output shows per-route JS size. Treat
  regressions as build failures.

## Environment + secrets

- `NEXT_PUBLIC_*` for client-exposed values only. Everything else is
  server-only.
- `env.mjs` with zod validation at app start (don't ship the app with
  missing env vars).
- Never log secrets, tokens, or full headers.

## Testing

- **Unit / component**: Vitest + Testing Library.
- **Route handlers**: test as async functions — mock `Request`, assert
  `Response`.
- **E2E**: Playwright. Run against `next build && next start`, not
  `next dev`.
- **Server Actions**: test by calling the function directly; assert
  DB / revalidate effects via mocks or test fixtures.

## Do not

- Do not use Pages Router (`pages/`) in new projects.
- Do not leave async segments without `loading.tsx` + `error.tsx`.
- Do not fetch in `useEffect` on a client component when the same data
  can be fetched in a parent Server Component.
- Do not import server-only modules (fs, db, env secrets) into code
  paths that might end up in a Client Component.
- Do not write hand-rolled `<title>` / `<meta>` tags — use the Metadata API.
- Do not ship `<img>` tags for content; always `next/image`.
- Do not mark a page `export const dynamic = "force-dynamic"` without
  a reason — it defeats streaming + caching.
