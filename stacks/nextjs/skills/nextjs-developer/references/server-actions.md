---
source: stacks/nextjs
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/nextjs-developer/references/server-actions.md
ported-at: 2026-04-17
adapted: true
---

# Server Actions

Server Actions are server-side functions callable from client or server
components. They replace most "API route + fetch + setState" patterns
for your own app.

## Shape

```ts
"use server";

export async function myAction(prev: State, formData: FormData): Promise<State> {
  // runs on the server, always
}
```

- Mark with `"use server"` at the top of the file, or as the first
  statement inside a function body.
- Serializable inputs: `FormData`, primitives, plain objects, Dates,
  typed arrays, `File` / `Blob`, arrays/objects of those.
- Returns must be serializable.

## File placement

- `app/actions.ts` — app-wide actions.
- `app/products/actions.ts` — feature-scoped actions.
- Colocated with a component (inside a `.tsx` file with `"use server"`
  on the function) — fine for 1-off actions.

## Using from a form (progressive enhancement)

```tsx
<form action={createProduct}>
  <input name="name" required />
  <button>Create</button>
</form>
```

Works with JavaScript disabled — the browser submits the form natively,
the server runs the action, and Next re-renders the page.

## Using with `useActionState`

```tsx
"use client";
import { useActionState } from "react";
import { createProduct } from "./actions";

export function NewProduct() {
  const [state, action, isPending] = useActionState(createProduct, {
    error: undefined,
  });
  return (
    <form action={action}>
      <input name="name" required />
      {state.error && <p role="alert">{state.error}</p>}
      <button disabled={isPending}>Create</button>
    </form>
  );
}
```

Preserves error state across submissions.

## Using programmatically

```tsx
"use client";
import { saveDraft } from "./actions";

function AutoSave({ content }: { content: string }) {
  const debouncedSave = useDebounce(saveDraft, 500);
  useEffect(() => {
    debouncedSave(content);
  }, [content, debouncedSave]);
  return null;
}
```

Actions are just functions. Call them from anywhere a Server Action is
allowed.

## Validation

Always validate on the server. The form's HTML constraints are a
convenience, not a trust boundary.

```ts
"use server";
import { z } from "zod";

const Schema = z.object({
  name: z.string().trim().min(1).max(120),
  price: z.coerce.number().positive(),
});

export async function createProduct(_prev: State, fd: FormData) {
  const parsed = Schema.safeParse({
    name: fd.get("name"),
    price: fd.get("price"),
  });
  if (!parsed.success) {
    return {
      error: "validation",
      fields: parsed.error.flatten().fieldErrors,
    };
  }
  // …
}
```

## Authorization

Every action checks the caller before doing work.

```ts
"use server";
import { getSession } from "@/lib/auth";

export async function deleteProduct(id: string) {
  const session = await getSession();
  if (!session?.user) return { error: "UNAUTHORIZED" };
  if (!session.user.canDeleteProducts) return { error: "FORBIDDEN" };

  await db.product.delete({ where: { id } });
  revalidateTag("products");
  return { ok: true };
}
```

Never derive authorization from a client-supplied token or hidden form
field. Read the session on the server.

## Revalidation

After a mutation, invalidate caches so next render is fresh.

- `revalidatePath("/products")` — specific path.
- `revalidatePath("/products/[id]", "page")` — route-group variant.
- `revalidateTag("products")` — all fetches tagged `"products"`.
- `revalidateTag("product:42")` — fine-grained per-entity.

Prefer tags for cross-route invalidation.

## Redirect + cookies

```ts
"use server";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

export async function login(_prev: State, fd: FormData) {
  const session = await authenticate(fd);
  if (!session) return { error: "invalid credentials" };

  (await cookies()).set("session", session.token, {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    path: "/",
    maxAge: 60 * 60 * 24,
  });
  redirect("/dashboard");
}
```

`redirect()` throws — nothing after it runs. Fine to call from inside
an action.

## Error handling

- Return typed state for **expected** errors (validation, forbidden,
  not-found). Let the client render them.
- Throw for **unexpected** errors (DB down). They surface in the
  nearest `error.tsx`.

Never let a DB exception reach the client verbatim — that's a PII /
infra leak.

## Forms vs. mutations outside forms

| Scenario | Pattern |
|---|---|
| Form submit | `<form action={myAction}>` |
| Form submit with state | `useActionState(myAction, initial)` |
| Button click mutation | `onClick={() => myAction(id)}` |
| Auto-save / programmatic | Call action inside an effect/timer |

All still run on the server. No API routes needed.

## Streaming + optimistic UI

Combine with `useOptimistic` for a snappy feel:

```tsx
"use client";
import { useOptimistic } from "react";
import { toggleLike } from "./actions";

export function LikeButton({ id, liked }: { id: string; liked: boolean }) {
  const [optimisticLiked, setOptimistic] = useOptimistic(liked);
  return (
    <form action={async () => {
      setOptimistic(!optimisticLiked);
      await toggleLike(id);
    }}>
      <button>{optimisticLiked ? "♥" : "♡"}</button>
    </form>
  );
}
```

## Rules

### Must do

- Validate inputs server-side in every action.
- Check authz before the DB.
- Use `revalidateTag` / `revalidatePath` after mutations.
- Return typed state for expected failures.
- Name files `actions.ts` (or put `"use server"` directive at top).

### Must not

- Don't call a Server Action from a Server Component directly —
  actions are for client → server calls. Inside server code, call the
  underlying function.
- Don't leak exceptions to the client. Catch, translate, return state.
- Don't forget revalidation — stale UI is a classic bug here.
- Don't use Server Actions as a replacement for public APIs consumed by
  other clients — use Route Handlers for those.
