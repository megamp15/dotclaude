---
source: stacks/nextjs
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/nextjs-developer/references/data-fetching.md
ported-at: 2026-04-17
adapted: true
---

# Data fetching + caching

Next.js App Router caching is powerful and opinionated. If you can't
state which cache tier applies to each fetch and why, you'll ship bugs.

## The four caches

| Cache | Scope | Controlled by |
|---|---|---|
| **Request memoization** | Per-request (dedupe within one render) | Automatic for `fetch`; `cache()` for others |
| **Data cache** | Persistent across requests (server) | `fetch` `cache` + `next.revalidate` + `next.tags` |
| **Full route cache** | Rendered HTML + RSC payload | Build + ISR + `revalidatePath` |
| **Client-side router cache** | SPA-like in-memory cache | `router.refresh()` to blow |

When in doubt, think in terms of the **data cache**: it's the tier you
configure per `fetch` call.

## `fetch` options

```ts
// always fresh — opts out of data cache
await fetch(url, { cache: "no-store" });

// cached permanently, revalidate on tag flush
await fetch(url, { next: { tags: ["products"] } });

// cached with ISR (60s)
await fetch(url, { next: { revalidate: 60 } });

// cached forever (explicit)
await fetch(url, { cache: "force-cache" });
```

Rules:
- **Every `fetch` has a cache policy.** Default changed in Next 15 to
  **no-store**. Be explicit.
- Use **tags** over paths for cross-route invalidation.
- Set a numeric `revalidate` only when the freshness interval is truly
  known — otherwise use tags + on-demand revalidation.

## Non-fetch data (DB, SDKs)

`fetch` is the happy path. For DB/SDK calls, use `unstable_cache` or
`cache`.

### `cache()` — per-request memoization

```tsx
import { cache } from "react";

export const getUserById = cache(async (id: string) => {
  return db.user.findUnique({ where: { id } });
});
```

Dedupes identical calls within a single request. Safe to use from
multiple components.

### `unstable_cache()` — cross-request + tag-invalidated

```tsx
import { unstable_cache } from "next/cache";

export const getProducts = unstable_cache(
  async () => db.product.findMany(),
  ["products:all"],               // cache key
  { tags: ["products"], revalidate: 60 },
);
```

Cache the *function*. Invalidate with `revalidateTag("products")`.

## On-demand revalidation

Two hooks: `revalidatePath` (path-based) and `revalidateTag`
(tag-based).

```ts
"use server";
import { revalidatePath, revalidateTag } from "next/cache";

export async function onMutate() {
  await doWork();

  // Revalidate a specific path
  revalidatePath("/products");

  // Revalidate all fetches/caches tagged "products"
  revalidateTag("products");
}
```

Rules:
- Prefer **tags** when the same data appears on multiple routes.
- Use **paths** for single-page UI where tags would be overkill.
- Revalidation is **deferred** — the invalidated caches are refilled on
  the next request.

## From webhooks (outside app)

Route handler triggers revalidation from an external system:

```ts
// app/api/webhooks/products/route.ts
import { revalidateTag } from "next/cache";

export async function POST(req: Request) {
  const secret = req.headers.get("x-secret");
  if (secret !== process.env.REVALIDATE_SECRET) {
    return Response.json({ error: "unauthorized" }, { status: 401 });
  }
  const { entity } = await req.json();
  revalidateTag(`${entity}:all`);
  return Response.json({ ok: true });
}
```

## Streaming with Suspense

Caches + Suspense combine for fast page loads:

```tsx
export default function Page() {
  return (
    <>
      <Header />
      <Suspense fallback={<Skeleton />}>
        <Products />
      </Suspense>
    </>
  );
}

async function Products() {
  const list = await fetch(api("/products"), {
    next: { tags: ["products"], revalidate: 60 },
  }).then((r) => r.json());
  return <List items={list} />;
}
```

- Header renders immediately (static / already-cached).
- `Products` streams when its data is ready.
- If `revalidate: 60` expires, the next request serves stale while
  revalidating in the background.

## Dynamic rendering

These APIs make a route dynamic (skip the full route cache):

- `cookies()` — reading request cookies.
- `headers()` — reading request headers.
- `searchParams` in a page.
- `fetch(..., { cache: "no-store" })` in the route.

Dynamic rendering is fine; it just means you don't get the full-route
cache. Use it intentionally, not by accident.

## Opting **into** dynamic at the segment

```tsx
export const dynamic = "force-dynamic";
```

Skips caching entirely for the segment. Use sparingly — document why.

## Opting **out** of dynamic

```tsx
export const dynamic = "force-static";
```

Fails build if the segment tries to use a dynamic API. Nice for
marketing pages you never want to go dynamic.

## `searchParams` gotcha

Reading `searchParams` makes the page dynamic. If you want the page to
stay static but want query-string-driven UI:

1. Use a client component with `useSearchParams()` for the reactive
   part.
2. Keep the shell server-rendered and static.

Or accept dynamic rendering if the search params materially affect
content.

## Cache tagging conventions

A consistent naming scheme pays off.

| Tag | Meaning |
|---|---|
| `products` | Any product-related data (broad invalidation) |
| `product:42` | Specific product (narrow invalidation) |
| `user:42:orders` | Per-user collection |

Tag at the granularity you'll invalidate. Over-tagging is cheap; under-
tagging forces path-based guesswork.

## Anti-patterns

- **Implicit caching assumptions.** Don't rely on "I think this is
  cached" — set the policy explicitly.
- **Manual `useEffect` + `useState` fetching** for data already
  available server-side. Move the fetch up.
- **Revalidating too aggressively** (`revalidate: 1`). You're just
  burning origin calls.
- **Forgetting `revalidateTag`** after a mutation. UI looks right but
  stays stale until the next natural revalidation.
- **Mixing `force-dynamic` + heavy fetches** — you're a slow SSR server
  at that point.

## Quick reference

| Goal | Pattern |
|---|---|
| Always fresh | `fetch(url, { cache: "no-store" })` |
| ISR, 60s | `fetch(url, { next: { revalidate: 60 } })` |
| Tag-invalidated | `fetch(url, { next: { tags: ["products"] } })` |
| Memoize DB call (per request) | `cache(fn)` |
| Memoize DB call (cross request) | `unstable_cache(fn, keys, { tags, revalidate })` |
| Invalidate one route | `revalidatePath("/foo")` |
| Invalidate all tagged | `revalidateTag("products")` |
| Blow client router cache | `router.refresh()` |
