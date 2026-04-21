---
source: stacks/nextjs
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/nextjs-developer/references/app-router.md
ported-at: 2026-04-17
adapted: true
---

# App Router — structure and routing

## Special files

| File | Purpose |
|---|---|
| `layout.tsx` | Shared UI wrapping `page.tsx` and descendants. Persists across navigations. |
| `template.tsx` | Like `layout.tsx` but remounts on navigation. Use for route transitions. |
| `page.tsx` | The leaf that owns a URL. |
| `loading.tsx` | Suspense fallback for the segment. |
| `error.tsx` | Error boundary for the segment (must be `"use client"`). |
| `global-error.tsx` | Catches root-layout errors. |
| `not-found.tsx` | Rendered when `notFound()` is called. |
| `route.ts` | Route handler — not a page. |
| `middleware.ts` (root) | Runs on each matched request. |

## Route segments

| Pattern | Meaning | Example |
|---|---|---|
| `foo/` | Static segment | `/foo` |
| `[id]` | Dynamic segment | `/foo/abc` |
| `[...slug]` | Catch-all | `/foo/a/b/c` |
| `[[...slug]]` | Optional catch-all | `/foo` and `/foo/x` |
| `(group)` | Route group (no URL impact) | — |
| `@slot` | Parallel route | — |
| `(.)foo` / `(..)foo` | Intercepted route | — |
| `_private` | Private (not routed) | — |

## Layouts

```tsx
// app/layout.tsx — root layout
export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
```

- The **root** layout is required.
- Layouts must include `<html>` and `<body>` tags **only** at the root.
- Layouts can fetch data; they render async.
- Layouts **don't** receive `params` for descendant dynamic segments —
  use `page.tsx` for those.

## Route groups

```
app/
├── (marketing)/
│   ├── layout.tsx
│   └── about/page.tsx
└── (app)/
    ├── layout.tsx
    └── dashboard/page.tsx
```

URLs: `/about`, `/dashboard`. Parentheses groups don't appear in URLs.

Use groups to:
- Apply different layouts to sections.
- Split a monorepo-like app into logical areas.
- Opt different sections into different caching/runtime options.

## Parallel routes

```
app/dashboard/
├── layout.tsx
├── @analytics/
│   ├── default.tsx
│   └── page.tsx
└── @team/
    ├── default.tsx
    └── page.tsx
```

Layout:

```tsx
export default function DashboardLayout({
  children,
  analytics,
  team,
}: {
  children: React.ReactNode;
  analytics: React.ReactNode;
  team: React.ReactNode;
}) {
  return (
    <div className="grid grid-cols-2 gap-4">
      <section>{analytics}</section>
      <section>{team}</section>
    </div>
  );
}
```

- Each slot streams independently with its own Suspense / error
  boundary.
- `default.tsx` renders when the parallel route isn't matched — always
  provide one.

## Intercepted routes

`(.)foo` matches from the same segment, `(..)foo` one level up, etc.
Useful for modals:

```
app/
├── photos/[id]/page.tsx             # full page view
└── feed/
    ├── page.tsx
    └── (..)photos/[id]/page.tsx     # modal overlay over /feed
```

Navigating from `/feed` to `/photos/42` shows a modal; a direct visit
to `/photos/42` shows the full page.

## Private folders

Prefix with `_` to exclude from routing:

```
app/
├── _components/Button.tsx
├── _lib/db.ts
└── page.tsx
```

Use for colocated non-route modules without leaking them as routes.

## Dynamic params (Next 15+)

Params are now **async**:

```tsx
// app/products/[id]/page.tsx
export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  // …
}
```

Same for `searchParams`. `generateMetadata` also receives them as a
Promise.

## `generateStaticParams`

```tsx
// app/products/[id]/page.tsx
export async function generateStaticParams() {
  const products = await db.product.findMany({ select: { id: true } });
  return products.map((p) => ({ id: p.id }));
}
```

Pre-renders the listed routes at build time. Combine with `dynamicParams`
for fallback behavior.

## `dynamicParams`, `dynamic`, `revalidate`

Segment-level config exports:

```tsx
export const dynamic = "force-static";     // or "error", "auto", "force-dynamic"
export const dynamicParams = true;          // generate unknown params on-demand
export const revalidate = 60;               // ISR
export const fetchCache = "default-cache";
export const runtime = "nodejs";            // or "edge"
export const preferredRegion = "auto";
```

Use sparingly. Defaults are usually right.

## Not-found, redirect, unauthorized

```tsx
import { notFound, redirect, unauthorized } from "next/navigation";

const product = await fetchProduct(id);
if (!product) notFound();

if (!session) redirect("/login");

if (!canAccess(session, product)) unauthorized();
```

Renders the corresponding `not-found.tsx` / navigates / renders
`unauthorized.tsx`.

## Nav + linking

```tsx
import Link from "next/link";
import { useRouter } from "next/navigation";

<Link href="/products" prefetch>
  Products
</Link>;

const router = useRouter();
router.push("/dashboard");
router.refresh(); // re-fetch current route
```

`next/navigation` in App Router, **not** `next/router` (that's Pages).

## Metadata at each segment

```tsx
// app/layout.tsx
export const metadata = { title: { default: "Acme", template: "%s | Acme" } };

// app/products/page.tsx
export const metadata = { title: "Products" }; // -> "Products | Acme"
```

## Checklist per segment

- [ ] `layout.tsx` if any shared UI.
- [ ] `page.tsx` if the segment is routable.
- [ ] `loading.tsx` if async.
- [ ] `error.tsx` if async.
- [ ] `not-found.tsx` if the route uses `notFound()`.
- [ ] `metadata` / `generateMetadata` for anything indexable.
- [ ] Right rendering knob: SSG / ISR / dynamic — chosen, not default.
