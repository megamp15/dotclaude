---
source: stacks/react
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/react-expert/references/server-components.md
ported-at: 2026-04-17
adapted: true
---

# Server Components

React Server Components (RSC) execute on the server, produce a
serialized tree, and stream it to the client. The client hydrates only
the interactive leaves. Used most often via Next.js App Router, but the
rules apply anywhere RSC is supported.

## Mental model

- Two component kinds live in the same tree: **Server** (default) and
  **Client** (opts in with `"use client"`).
- Data fetching, file I/O, secrets, heavy computation → Server.
- State, effects, refs, event handlers, browser APIs → Client.
- The boundary between them is a single directive at the top of a file.

## Opting in to client

```tsx
"use client";

import { useState } from "react";
export function Counter() {
  const [n, setN] = useState(0);
  return <button onClick={() => setN(n + 1)}>{n}</button>;
}
```

Put `"use client"` **only** on files that need it. Every descendant of a
client module is client too — cascade is automatic.

## Data fetching in Server Components

```tsx
// app/users/page.tsx — runs on the server
import { db } from "@/lib/db";

export default async function UsersPage() {
  const users = await db.user.findMany({ where: { active: true } });
  return (
    <ul>
      {users.map((u) => (
        <li key={u.id}>{u.name}</li>
      ))}
    </ul>
  );
}
```

- Top-level `await` is fine.
- No hooks, no state, no effects.
- Secrets (DB URL, API keys) are safe here — they never reach the client.
- Errors thrown here propagate to the nearest `error.tsx` boundary.

## Passing data between Server and Client

### Server → Client (via props)

```tsx
// Server
import { getUser } from "@/lib/db";
import { ProfileCard } from "./ProfileCard"; // client

export default async function Page() {
  const user = await getUser();
  return <ProfileCard user={user} />;
}
```

Props must be **serializable**. Allowed:
- Primitives, arrays, plain objects, `Date`, `BigInt`, typed arrays,
  `Map`, `Set`, `RegExp`, `Promise`, JSX, Server Actions (opaque refs).

Not allowed: functions (except Server Actions), class instances, symbols
that aren't the well-known ones.

### Client → Server (via Server Actions)

```tsx
// actions.ts
"use server";

export async function createPost(formData: FormData) {
  // runs on the server, still a function identity from the client
}
```

```tsx
// ClientForm.tsx
"use client";
import { createPost } from "./actions";

export function ClientForm() {
  return (
    <form action={createPost}>
      <input name="title" />
      <button>Create</button>
    </form>
  );
}
```

Server Actions are the only "functions" allowed to cross from client to
server.

## Nesting rules

- A **Server Component** can import + render Client Components.
- A **Client Component** can render Server Components **only as
  `children` props** — not imported directly.

```tsx
// Server
export default async function Layout({ children }) {
  const user = await getUser();
  return (
    <ClientShell user={user}>
      {children /* may contain Server Components */}
    </ClientShell>
  );
}

// Client
"use client";
export function ClientShell({ user, children }) {
  return (
    <div>
      <Header user={user} />
      {children}
    </div>
  );
}
```

This pattern keeps server-rendered subtrees out of the client bundle.

## Suspense streaming

Server Components compose naturally with Suspense:

```tsx
export default function Page() {
  return (
    <>
      <Header />
      <Suspense fallback={<Skeleton />}>
        <SlowList /> {/* async Server Component */}
      </Suspense>
    </>
  );
}
```

The header streams immediately; the list streams when ready. No loading
state code.

## Common mistakes

- **Blanket `"use client"` on a layout.** Turns every page into a client
  bundle. Push the directive down to leaves.
- **Reading `cookies()` / `headers()` in a Client Component.** These are
  server-only. Read them in a Server Component and pass the value as a
  prop.
- **Passing a function as a prop across the boundary.** Only Server
  Actions are allowed.
- **Tying data fetching to `useEffect` in a client leaf** when the data
  was already available on the server. Move the fetch up.
- **Using `useRouter` from `next/router`** (pages router) in App Router.
  Use `next/navigation`.

## When NOT to use RSC

- Highly interactive dashboards with rich client-state.
- SPAs with no SSR in the picture.
- Apps where the SEO + TTFB wins don't offset the RSC complexity.

An SPA with TanStack Query is still an excellent default for many apps.
Don't adopt RSC because it's new; adopt it because the page is
data-heavy, SEO matters, or TTFB / streaming are business requirements.

## Checklist

- [ ] Every file either has `"use client"` at the top or is Server by
      default — no mystery files.
- [ ] Props across the boundary are serializable.
- [ ] Secrets stay server-side.
- [ ] Server Actions (not functions) handle mutations from clients.
- [ ] Suspense used for slow subtrees; ErrorBoundary paired for failures.
- [ ] `error.tsx` / `not-found.tsx` handled at each route segment.
