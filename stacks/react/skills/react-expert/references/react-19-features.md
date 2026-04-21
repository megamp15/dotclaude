---
source: stacks/react
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/react-expert/references/react-19-features.md
ported-at: 2026-04-17
adapted: true
---

# React 19 features

Four pieces change how you write forms and async UI: `useActionState`,
`useFormStatus`, `useOptimistic`, and `use()`.

## `useActionState`

Replaces the `onSubmit` + `useState` boilerplate for form submissions.

```tsx
const [state, action, isPending] = useActionState(reducer, initialState);
```

Signature: `reducer(prevState, formData) → nextState`.

```tsx
"use client";
import { useActionState } from "react";

async function submit(
  prev: { error?: string },
  formData: FormData,
): Promise<{ error?: string; ok?: true }> {
  const email = formData.get("email") as string;
  if (!email.includes("@")) return { error: "invalid email" };

  const res = await fetch("/api/subscribe", {
    method: "POST",
    body: formData,
  });
  if (!res.ok) return { error: await res.text() };
  return { ok: true };
}

export function SubscribeForm() {
  const [state, action, isPending] = useActionState(submit, {});
  return (
    <form action={action}>
      <input name="email" required />
      {state.error && <p role="alert">{state.error}</p>}
      {state.ok && <p role="status">Subscribed!</p>}
      <button disabled={isPending}>Subscribe</button>
    </form>
  );
}
```

Why it's better:
- No `useState` for form data, error, or isPending.
- Previous state is first-class — easy to accumulate or roll back.
- Works with Server Actions for zero-JS progressive enhancement.

## `useFormStatus`

A child of a `<form>` can read the parent's submission status — no prop
drilling.

```tsx
"use client";
import { useFormStatus } from "react-dom";

export function SubmitButton({ children }: { children: React.ReactNode }) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending}>
      {pending ? "Saving…" : children}
    </button>
  );
}
```

Use for submit buttons, pending banners, field-level disable states.
`useFormStatus` must be used inside a component rendered **within** a
`<form>` — not on the form itself.

## `useOptimistic`

Apply a speculative UI update while a mutation is in flight, roll back on
failure.

```tsx
"use client";
import { useOptimistic } from "react";

export function TodoList({ todos, addTodo }) {
  const [optimisticTodos, addOptimistic] = useOptimistic(
    todos,
    (state, newTodo) => [...state, { ...newTodo, sending: true }],
  );

  async function action(formData: FormData) {
    const text = formData.get("text") as string;
    addOptimistic({ id: crypto.randomUUID(), text });
    await addTodo(text);
  }

  return (
    <>
      <ul>
        {optimisticTodos.map((t) => (
          <li key={t.id} style={{ opacity: t.sending ? 0.5 : 1 }}>
            {t.text}
          </li>
        ))}
      </ul>
      <form action={action}>
        <input name="text" required />
        <button>Add</button>
      </form>
    </>
  );
}
```

Pair with a real server action. On rollback, React re-renders with the
authoritative `todos` automatically.

## `use()`

Conditionally unwrap a Promise or Context. Works in `if` / `for` /
anywhere — unlike normal hooks.

```tsx
"use client";
import { use } from "react";

export function Profile({ promise }: { promise: Promise<User> }) {
  const user = use(promise);
  return <div>{user.name}</div>;
}
```

Pattern:

```tsx
// Server Component
export default function Page() {
  const promise = fetchUser(); // not awaited
  return (
    <Suspense fallback={<Skeleton />}>
      <Profile promise={promise} />
    </Suspense>
  );
}
```

The promise is created on the server, passed to a client leaf, and
unwrapped there via `use()`. Suspense handles loading, ErrorBoundary
handles rejection.

## Server Actions

Defined with `"use server"`, callable from client components. They're the
only function-like primitive that crosses the server → client boundary.

```tsx
// actions.ts
"use server";
export async function createItem(formData: FormData) {
  await db.items.create({ name: formData.get("name") });
  revalidatePath("/items"); // Next.js App Router
}
```

```tsx
// Client
"use client";
import { createItem } from "./actions";
export function NewItemForm() {
  return (
    <form action={createItem}>
      <input name="name" />
      <button>Create</button>
    </form>
  );
}
```

## Form compatibility

`<form action={serverAction}>` works **without JS** — the form submits
as a native POST, the action runs on the server, the page re-renders.
Progressive enhancement is back.

## Migration tips

| Old pattern | React 19 equivalent |
|---|---|
| `useState` + `onSubmit` + `fetch` + `useState` for error | `useActionState` |
| `isPending` state threaded through children | `useFormStatus` |
| Manual optimistic update + rollback | `useOptimistic` |
| `useEffect` to read a Context conditionally | `use(Context)` |
| `useEffect` to unwrap a passed Promise | `use(promise)` + Suspense |

## Rules

- Don't mix `useActionState` with a parallel `useState` for the same form —
  let one mechanism own submission state.
- `useFormStatus` must be **inside** the form's subtree, not on the
  form itself.
- `useOptimistic` is for optimistic UI — not for permanent state. Source
  of truth stays on the server.
- `use()` suspends — it must be inside a Suspense boundary with an
  ErrorBoundary above.
