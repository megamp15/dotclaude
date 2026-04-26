---
source: stacks/nextjs
name: nextjs-patterns
description: Next.js 14+ App Router patterns and anti-patterns. Load when writing or reviewing App Router routes, Server Components, Server Actions, route handlers, or Next-specific config.
triggers: next.js, nextjs, app router, server action, use server, route handler, generateMetadata, revalidatePath, revalidateTag, next/image, next/font, edge runtime, ISR, RSC, middleware.ts
globs: ["**/app/**/*.{ts,tsx}", "**/next.config.{js,mjs,ts}", "**/middleware.{ts,tsx}"]
---

# Next.js App Router patterns

The subset of Next.js conventions worth enforcing as rules (vs. taste).

> **See also:** `stacks/nextjs/skills/nextjs-developer/` — deep-dive skill
> for rendering strategy selection, Server Actions workflow, deployment,
> and Core Web Vitals triage.

## Rendering strategy — the decision tree

```
Is the page personalized per request?
  └─ Yes → dynamic rendering (cookies/headers used, or cache: "no-store")
  └─ No → is it rebuild-time static?
            └─ Yes → SSG (generateStaticParams + default cache)
            └─ No → ISR (fetch with next.revalidate, or revalidateTag)
```

Never `export const dynamic = "force-dynamic"` unless you can justify it
in a comment. It disables streaming + caching for the whole segment.

## `loading.tsx` + `error.tsx` + `not-found.tsx`

Every async segment:

```
app/products/
├── page.tsx          # async server component
├── loading.tsx       # Suspense fallback
├── error.tsx         # error boundary (client component, "use client")
└── not-found.tsx     # 404 for notFound()
```

Missing `loading.tsx` → user stares at a blank page while streaming.
Missing `error.tsx` → crash bubbles to the root boundary (ugly).

```tsx
// error.tsx
"use client";

export default function Error({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <div>
      <p>Something went wrong.</p>
      <button onClick={reset}>Try again</button>
    </div>
  );
}
```

## `generateMetadata` for SEO

```tsx
// app/products/[id]/page.tsx
import type { Metadata } from "next";

export async function generateMetadata(
  { params }: { params: Promise<{ id: string }> },
): Promise<Metadata> {
  const { id } = await params;
  const product = await fetchProduct(id);
  if (!product) return { title: "Not found" };
  return {
    title: product.name,
    description: product.description,
    openGraph: {
      title: product.name,
      description: product.description,
      images: [{ url: product.imageUrl }],
    },
    alternates: { canonical: `/products/${id}` },
  };
}
```

**Never** hand-write `<title>` or `<meta>` in JSX. Use the Metadata API.

## Server Actions — the pattern

```tsx
// app/products/actions.ts
"use server";

import { revalidatePath } from "next/cache";
import { z } from "zod";

const CreateProductSchema = z.object({
  name: z.string().min(1).max(120),
  price: z.coerce.number().positive(),
});

export async function createProduct(
  _prev: { error?: string },
  formData: FormData,
) {
  const parsed = CreateProductSchema.safeParse({
    name: formData.get("name"),
    price: formData.get("price"),
  });
  if (!parsed.success) {
    return { error: parsed.error.issues[0]?.message ?? "invalid input" };
  }

  await db.product.create({ data: parsed.data });
  revalidatePath("/products");
  return { error: undefined };
}
```

```tsx
// app/products/new/page.tsx
"use client";
import { useActionState } from "react";
import { createProduct } from "../actions";

export default function NewProductPage() {
  const [state, action] = useActionState(createProduct, { error: undefined });
  return (
    <form action={action}>
      <input name="name" required />
      <input name="price" type="number" required />
      {state.error && <p role="alert">{state.error}</p>}
      <SubmitButton />
    </form>
  );
}
```

Rules:
- Validate inputs server-side — always.
- Always `revalidatePath` or `revalidateTag` after a mutation.
- Don't return `Error` objects from actions — return serializable
  state.
- Server Actions can be called from a `<form action={...}>` and work
  with no JS — don't break progressive enhancement with client-only
  logic.

## Data fetching — explicit caching

```tsx
// always-fresh
const res = await fetch(url, { cache: "no-store" });

// cached permanently until manually revalidated
const res = await fetch(url, { next: { tags: ["products"] } });

// ISR every 60s
const res = await fetch(url, { next: { revalidate: 60 } });
```

Every `fetch()` in server code has a cache policy. If you can't state
which one and why, you shouldn't ship it.

## Cache invalidation

- `revalidatePath("/products")` — blow the cache for a specific path.
- `revalidateTag("products")` — blow all fetches tagged `"products"`.
- `unstable_cache(fn, keys, { tags, revalidate })` — cache a function
  with tag-based invalidation.

Prefer tags for cross-route invalidation (e.g. a single product mutation
should invalidate the detail page **and** the list page).

## Client/server boundary anti-patterns

### Blanket `"use client"` at the layout

```tsx
// BAD — everything below is a client component
"use client";
export default function Layout({ children }) { /* … */ }
```

Push `"use client"` to the leaves.

### Server-only code imported by a client component

```tsx
// BAD — Prisma shipped to the client
"use client";
import { db } from "@/lib/db"; // ← server-only
```

Use `import "server-only"` at the top of server modules to fail fast
if they leak into the client bundle.

### Fetching in `useEffect` for data already available on the server

```tsx
// BAD — client round-trip for data the RSC could have fetched
"use client";
useEffect(() => {
  fetch("/api/products").then(...)
}, []);

// GOOD — server component fetches, passes props
// app/products/page.tsx (server)
const products = await fetchProducts();
return <ProductList products={products} />;
```

## Route handlers (`app/api/.../route.ts`)

```ts
// app/api/webhooks/stripe/route.ts
import { NextRequest } from "next/server";
import { verifyStripeSignature } from "@/lib/stripe";

export const runtime = "nodejs"; // or "edge"

export async function POST(req: NextRequest) {
  const body = await req.text();
  const sig = req.headers.get("stripe-signature");
  if (!verifyStripeSignature(body, sig)) {
    return Response.json({ error: "invalid" }, { status: 400 });
  }
  // process…
  return Response.json({ ok: true });
}
```

Use route handlers for webhooks and external integrations. Inside your
own React app, prefer Server Actions — they're leaner and typesafe.

## Images

```tsx
import Image from "next/image";

<Image
  src={product.imageUrl}
  alt={product.name}
  width={400}
  height={300}
  priority={isHero}
/>
```

- Always `alt`.
- Always `width` + `height` (or `fill`).
- `priority` for above-the-fold LCP images.
- Remote hosts must be declared in `next.config.js` `images.remotePatterns`.

## Fonts

```tsx
import { Inter } from "next/font/google";
const inter = Inter({ subsets: ["latin"], display: "swap" });
```

Use `next/font` everywhere. It self-hosts Google Fonts, prevents CLS,
and avoids render-blocking requests.

## Middleware

```ts
// middleware.ts
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(req: NextRequest) {
  const token = req.cookies.get("session")?.value;
  if (!token && req.nextUrl.pathname.startsWith("/admin")) {
    return NextResponse.redirect(new URL("/login", req.url));
  }
  return NextResponse.next();
}

export const config = { matcher: ["/admin/:path*"] };
```

Keep middleware small — it runs on every matched request. Don't read
the DB here.

## Environment

```ts
// env.mjs
import { z } from "zod";
const schema = z.object({
  DATABASE_URL: z.string().url(),
  STRIPE_SECRET: z.string().min(1),
  NEXT_PUBLIC_SITE_URL: z.string().url(),
});
export const env = schema.parse(process.env);
```

App fails to boot with missing/invalid env. That's the point.

## Do not

- Do not use `pages/` in new projects.
- Do not omit `loading.tsx` / `error.tsx` on async segments.
- Do not hand-write `<title>` / `<meta>` in JSX.
- Do not ship a Prisma/db import into a Client Component.
- Do not `useEffect`-fetch data that a parent Server Component could
  load.
- Do not `export const dynamic = "force-dynamic"` without a comment
  explaining why.
- Do not use `<img>` for content images — `next/image` always.
- Do not read secrets from `process.env` without validation — route
  all env through a validated schema.
