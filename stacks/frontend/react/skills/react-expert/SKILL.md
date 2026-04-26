---
name: react-expert
description: Deep React 19+ expertise — Server Components, Suspense + ErrorBoundary composition, React 19 form actions (`useActionState`, `useFormStatus`), `use()` hook, TanStack Query patterns, class → hooks migration, and performance triage. Extends the rules in `stacks/react/rules/react-patterns.md` with richer design guidance.
source: stacks/react
triggers: /react-expert, React 19, Server Components, RSC, useActionState, useFormStatus, use() hook, Suspense boundary, TanStack Query, migrate class component, React performance
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/react-expert
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# react-expert

You write and review React 19+ code. `stacks/react/rules/react-patterns.md`
covers the baseline (hooks rules, anti-patterns, "when to reach for what"
state decisions). This skill is the deep-dive: architectural patterns
that need more than a rules list.

## When this skill is the right tool

- Designing the component + data-fetching architecture for a new feature
- Migrating class components (or `connect()`-style Redux) to modern React
- Debugging hard re-render problems (React DevTools Profiler work)
- Deciding between RSC + Server Actions vs. client + TanStack Query
- Building form flows with React 19 actions (`useActionState`,
  `useFormStatus`, `use()`)
- Setting up Suspense boundaries that interact correctly with routing

**Not for:**
- Baseline patterns already in `react-patterns.md` — read that first.
- Styling decisions — decided at stack level (`CLAUDE.stack.md`).
- Next.js-specific App Router, metadata, route handlers →
  `stacks/nextjs/skills/nextjs-developer`.

## Core workflow

1. **Analyze.** Component hierarchy, props flow, state needs, async
   boundaries. Decide which leaves are interactive (client) vs. rendered
   once (server, when using RSC).
2. **Pick patterns.** State (local / shared / server), data fetching
   (TanStack Query / SWR / RSC), async boundaries (Suspense +
   ErrorBoundary pairs).
3. **Implement with TypeScript strict.**
4. **Typecheck.** `tsc --noEmit`. Fix errors before committing.
5. **Optimize only when measured.** Use React DevTools Profiler.
6. **Test.** Testing Library — query by role, user-event for interactions.

## React 19 essentials

### Form actions (`useActionState` + `useFormStatus`)

Prefer actions over hand-rolled `onSubmit` + `useState`.

```tsx
"use client";
import { useActionState } from "react";
import { useFormStatus } from "react-dom";

async function submitForm(
  _prev: { message: string },
  formData: FormData,
): Promise<{ message: string }> {
  const name = formData.get("name") as string;
  await fetch("/api/greet", {
    method: "POST",
    body: JSON.stringify({ name }),
    headers: { "Content-Type": "application/json" },
  });
  return { message: `Hello, ${name}!` };
}

export function GreetForm() {
  const [state, action] = useActionState(submitForm, { message: "" });
  return (
    <form action={action}>
      <input name="name" required aria-label="Your name" />
      <SubmitButton />
      {state.message && <p role="status">{state.message}</p>}
    </form>
  );
}

function SubmitButton() {
  const { pending } = useFormStatus();
  return (
    <button type="submit" disabled={pending}>
      {pending ? "Submitting…" : "Submit"}
    </button>
  );
}
```

Action functions:
- Receive `prevState` as the first arg — use it for error messages across
  submissions.
- Run on the server when paired with Server Actions in frameworks like
  Next.js.
- Return a new state object — no `setState` call needed.

### `use()` hook

Unwraps Promises and Contexts conditionally. Works in Client Components
and can be called inside `if`/`for` — unlike normal hooks.

```tsx
"use client";
import { use } from "react";

export function Profile({ userPromise }: { userPromise: Promise<User> }) {
  const user = use(userPromise);
  return <div>{user.name}</div>;
}
```

Wrap with a Suspense boundary. The promise typically comes from a Server
Component.

### Server Components (framework-agnostic rules)

- Default is server. Opt in to client with `"use client"` only at the
  leaves that need interactivity.
- Server Components can be `async` — top-level `await` works.
- Props that cross the server → client boundary must be **serializable**.
  Functions can't cross. Use Server Actions for mutations.
- A Server Component can render a Client Component; a Client Component
  can render Server Components only when they're passed as `children`,
  not imported directly.
- Don't `"use client"` a whole layout to unlock one interactive widget.

## Suspense + ErrorBoundary composition

```tsx
<ErrorBoundary fallback={<ErrorState />}>
  <Suspense fallback={<Skeleton />}>
    <UserProfile userId={userId} />
  </Suspense>
</ErrorBoundary>
```

- Suspense handles the "loading" branch.
- ErrorBoundary handles the "failed" branch.
- Neither without the other is complete.
- Place boundaries at **route** and **feature** seams, not around every
  leaf. Too many boundaries fragment the UX.

## Custom hooks — the contract

A custom hook is an API. Treat it like one:

```tsx
function useSelection<T>(items: T[], isEqual: (a: T, b: T) => boolean) {
  const [selected, setSelected] = useState<T | null>(null);

  const toggle = useCallback(
    (item: T) => {
      setSelected((curr) => (curr && isEqual(curr, item) ? null : item));
    },
    [isEqual],
  );

  const isSelected = useCallback(
    (item: T) => !!selected && isEqual(selected, item),
    [selected, isEqual],
  );

  return { selected, toggle, isSelected } as const;
}
```

Rules:
- Name starts with `use`.
- Inputs are explicit; return value is stable in shape.
- Don't put side-effect state inside a hook that callers forget to clean
  up. Provide cleanup or make the hook idempotent.
- Generic parameters are opt-in power. Don't force `<T>` where concrete
  types are clearer.

See `references/hooks-patterns.md` for more.

## Performance triage

Symptom-first. Don't pre-optimize.

1. **Profile first.** React DevTools → Profiler → record the slow interaction.
2. **Identify the re-render cause** — flame graph shows which components
   and why (props, state, hooks).
3. **Fix the cause, not the symptom**:
   - New prop identity each render? Stabilize with `useMemo` /
     `useCallback` **only at the memoization boundary**.
   - Context value changes too often? Split the context.
   - Expensive render work? `useMemo`, or lift the work above React
     (web worker, server-computed).
   - Huge list? Virtualize (TanStack Virtual, react-window).
4. **Verify** by re-profiling. If you can't see the win in the profiler,
   the optimization isn't one.

Full cheat sheet in `references/performance.md`.

## Class → modern migration

See `references/class-to-modern.md`. Rough recipe:

| Class concept | Modern equivalent |
|---|---|
| `state` object | `useState` / `useReducer` |
| `componentDidMount` | `useEffect(fn, [])` |
| `componentDidUpdate(prevProps)` | `useEffect(fn, [dep])` |
| `componentWillUnmount` | cleanup function returned from `useEffect` |
| `getDerivedStateFromProps` | compute in render, or `key` to remount |
| `shouldComponentUpdate` | `React.memo` + stable props |
| `getSnapshotBeforeUpdate` | `useLayoutEffect` (measure before paint) |
| `componentDidCatch` | ErrorBoundary (still class) or third-party boundary |
| `connect()` from Redux | `useSelector` / `useDispatch` / RTK Query |

## Rules

### Must do

- TypeScript strict mode.
- ErrorBoundary at each feature seam; Suspense inside.
- Stable `key`s (no index for dynamic lists).
- `useEffect` cleanup whenever the effect subscribes or times out.
- Semantic HTML first, ARIA only when needed.
- Memoize at the boundary that reaches a memoized child (not everywhere).

### Must not

- Fetch data in `useEffect` when TanStack Query / SWR is available.
- Mutate state directly — always return a new value.
- `key={index}` on dynamic lists.
- Create functions in JSX that are passed to memoized children.
- Sprinkle `useMemo` / `useCallback` prophylactically.
- Leave Suspense without an ErrorBoundary (or vice versa).
- Convert every class component at once — migrate feature by feature.

## References

| Topic | File |
|---|---|
| Server Components patterns (framework-agnostic + App Router specifics) | `references/server-components.md` |
| React 19 features (`useActionState`, `useFormStatus`, `use()`) | `references/react-19-features.md` |
| Custom hook design + testing | `references/hooks-patterns.md` |
| Performance triage (profiler → cause → fix) | `references/performance.md` |
| Class-to-modern migration recipe | `references/class-to-modern.md` |

## See also

- Baseline React rules → `stacks/react/rules/react-patterns.md`
- Next.js App Router specifics → `stacks/nextjs/skills/nextjs-developer`
- Full-stack feature flow → `core/skills/fullstack-guardian`
