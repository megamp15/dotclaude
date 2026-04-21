---
name: nextjs-developer
description: Deep Next.js 14+ App Router expertise — App Router layout design, rendering strategy selection (SSR/SSG/ISR/streaming), Server Actions + Server Components workflow, route handlers, middleware, and deployment. Extends the rules in `stacks/nextjs/rules/nextjs-patterns.md`.
source: stacks/nextjs
triggers: /nextjs, Next.js 14, App Router, server action, route handler, middleware, edge runtime, generateMetadata, revalidatePath, revalidateTag, next/image, next/font, Vercel deploy
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/nextjs-developer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# nextjs-developer

You design and implement Next.js 14+ App Router features. Baseline
rules (the "what" and the "do / don't") live in
`stacks/nextjs/rules/nextjs-patterns.md`. This skill is the deep-dive:
architecture decisions that need more than a rules list.

## When this skill is the right tool

- Planning the folder + routing layout for a new Next.js app
- Choosing a rendering strategy per route (SSG / ISR / SSR / dynamic)
- Designing a Server Actions-based data flow end-to-end
- Wiring route handlers for webhooks and external integrations
- Triaging Core Web Vitals regressions after a build

**Not for:**
- Baseline lint-style rules — see `nextjs-patterns.md`.
- Generic React patterns — see `stacks/react/`.
- Full-stack feature implementation — pair with `core/skills/fullstack-guardian`.

## Core workflow

1. **Plan the app structure.** Routes, layouts, groups, shared segments.
2. **Decide rendering per route.** Use the decision tree below.
3. **Wire data fetching.** RSC + `fetch` with explicit caching; Server
   Actions for mutations.
4. **Add the boundaries.** `loading.tsx`, `error.tsx`, `not-found.tsx`
   on every async segment.
5. **Optimize.** Images via `next/image`, fonts via `next/font`, bundle
   audit, edge runtime where it helps.
6. **Validate.** `next build` locally; confirm zero type errors; check
   per-route bundle sizes; run Lighthouse / PageSpeed on key routes.
7. **Deploy.** Vercel by default, self-host when needed; verify env
   vars set, domains mapped, analytics on.

## Rendering strategy decision tree

```
Is this request personalized per user?
 └─ Yes
      └─ Are the personal bits a small subtree?
            └─ Yes → RSC page + client island (Suspense streaming)
            └─ No  → Dynamic rendering (cookies/headers read server-side)
 └─ No
      └─ Do we know all params at build time?
            └─ Yes → SSG (generateStaticParams)
            └─ No  → ISR (fetch next.revalidate, or revalidateTag)
```

Ground rules:
- Default is "as static as possible" for cacheability and cost.
- Prefer **tag-based** revalidation so one mutation updates many routes.
- `export const dynamic = "force-dynamic"` is a last resort. Document
  why whenever you use it.

## App Router layout patterns

### Route groups (parentheses) for shared layouts without URL impact

```
app/
├── (marketing)/
│   ├── layout.tsx        # marketing nav / footer
│   ├── page.tsx          # /
│   └── about/page.tsx    # /about
├── (app)/
│   ├── layout.tsx        # authenticated shell
│   ├── dashboard/page.tsx
│   └── settings/page.tsx
└── login/page.tsx
```

Route groups don't appear in URLs but let you apply different layouts
to different sections of the same app.

### Parallel routes (`@slot`) for side-by-side independent regions

```
app/dashboard/
├── layout.tsx
├── @analytics/page.tsx
└── @team/page.tsx
```

Use for dashboards where regions load independently and have their own
Suspense + error boundaries.

### Intercepted routes (`(..)foo`) for modal-style overlays

Use when navigating to a URL should render a modal on top of the current
page (e.g. photo gallery detail views).

## Data fetching patterns

### Parallel fetches

```tsx
// app/dashboard/page.tsx
export default async function Page() {
  const [stats, recent] = await Promise.all([
    fetchStats(),
    fetchRecent(),
  ]);
  return (
    <>
      <Stats data={stats} />
      <Recent data={recent} />
    </>
  );
}
```

### Sibling Suspense streaming (faster TTFB)

```tsx
export default function Page() {
  return (
    <>
      <Suspense fallback={<StatsSkeleton />}>
        <Stats />
      </Suspense>
      <Suspense fallback={<RecentSkeleton />}>
        <Recent />
      </Suspense>
    </>
  );
}

async function Stats() { const data = await fetchStats(); return <StatsView data={data} />; }
async function Recent() { const data = await fetchRecent(); return <RecentView data={data} />; }
```

Each subtree streams when its data is ready. Slow one doesn't hold back
the fast one.

### Request-scoped caching

```tsx
import { cache } from "react";
import { db } from "@/lib/db";

export const getUserById = cache(async (id: string) => {
  return db.user.findUnique({ where: { id } });
});
```

`cache()` dedupes within a single request. Safe to call from multiple
components in one render.

## Server Actions — end-to-end flow

```tsx
// app/products/actions.ts
"use server";
import { z } from "zod";
import { revalidateTag } from "next/cache";
import { getUser } from "@/lib/auth";

const Schema = z.object({
  name: z.string().min(1).max(120),
  price: z.coerce.number().positive(),
});

export async function createProduct(
  _prev: { error?: string },
  formData: FormData,
) {
  const user = await getUser();
  if (!user?.canCreateProducts) {
    return { error: "forbidden" };
  }

  const parsed = Schema.safeParse({
    name: formData.get("name"),
    price: formData.get("price"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "invalid input" };
  }

  await db.product.create({ data: parsed.data });
  revalidateTag("products");
  return { error: undefined };
}
```

Client uses `useActionState` — see `stacks/react/skills/react-expert`
for the hook details.

Rules to hold the line on:
- **Authz first** — every server action checks the caller's permissions
  before touching the DB.
- **Server-side validation** — always. Zod or Valibot at the boundary.
- **Tagged invalidation** — use `revalidateTag` over `revalidatePath`
  for cross-route freshness.
- **No `throw` for expected failures** — return typed state so forms
  can show errors with progressive enhancement.

## Middleware

```ts
// middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";
import { verifyJwt } from "@/lib/auth";

const PROTECTED = ["/dashboard", "/settings"];

export async function middleware(req: NextRequest) {
  const path = req.nextUrl.pathname;
  if (!PROTECTED.some((p) => path.startsWith(p))) return NextResponse.next();

  const token = req.cookies.get("session")?.value;
  const ok = token && (await verifyJwt(token));
  if (!ok) {
    const url = new URL("/login", req.url);
    url.searchParams.set("next", path);
    return NextResponse.redirect(url);
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/dashboard/:path*", "/settings/:path*"],
};
```

Middleware runs at the edge, pre-route-resolution. Keep it tiny: auth
checks, redirects, rewrites, simple header injection. No DB calls, no
heavy work.

## Core Web Vitals triage

When Lighthouse / PageSpeed regresses:

1. **LCP (largest contentful paint)**
   - Is the LCP image optimized with `next/image priority`?
   - Is the LCP rendered server-side (no client-only render)?
   - Is the font flashing? Use `next/font` with `display: "swap"`.

2. **CLS (cumulative layout shift)**
   - Every image has explicit `width`/`height` (or `fill` + CSS sizing).
   - Ads/embeds have reserved space.
   - No `font-display: optional` without testing.

3. **INP (interaction to next paint)**
   - Heavy client components hydrating late — move to RSC, or split
     with `dynamic(() => import(...), { ssr: false })` for below-fold.
   - Long tasks in event handlers — defer with `startTransition` or
     offload to a worker.

4. **TTFB**
   - Dynamic rendering on a page that could be ISR.
   - Slow DB queries in a Server Component — add a Suspense boundary,
     cache, or revalidate tag.
   - Cold start on edge runtime — consider Node runtime for that route.

## Deployment

### Vercel (default)

- Each branch → preview deployment.
- Env vars per environment.
- Analytics + Speed Insights built in.
- `vercel.json` only when you need custom routing/headers.

### Self-host (Docker)

```dockerfile
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json pnpm-lock.yaml ./
RUN corepack enable && pnpm install --frozen-lockfile

FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN corepack enable && pnpm next build

FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs \
 && adduser --system --uid 1001 nextjs
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]
```

Requires `output: "standalone"` in `next.config.js`. Ship thin images;
no `node_modules` in the runner stage.

## References

| Topic | File |
|---|---|
| App Router structure and routing patterns | `references/app-router.md` |
| Server Components + streaming + boundaries | `references/server-components.md` |
| Server Actions (mutations, revalidation, progressive enhancement) | `references/server-actions.md` |
| Caching + data fetching (ISR, tags, `unstable_cache`) | `references/data-fetching.md` |
| Deployment — Vercel + self-host + edge considerations | `references/deployment.md` |

## See also

- Rules → `stacks/nextjs/rules/nextjs-patterns.md`
- Generic React → `stacks/react/` + `stacks/react/skills/react-expert`
- Full-stack feature flow → `core/skills/fullstack-guardian`
