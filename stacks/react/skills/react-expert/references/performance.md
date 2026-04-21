---
source: stacks/react
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/react-expert/references/performance.md
ported-at: 2026-04-17
adapted: true
---

# Performance triage

Symptom → profile → cause → fix → re-profile.

## Step 1: Profile

Open React DevTools → **Profiler** → record the slow interaction. The
flame graph shows:

- Which components rendered.
- How long each took.
- *Why* it rendered (hover a component → "Why did this render?").

"Re-renders are slow" is a feeling. The profiler is the fact.

## Step 2: Identify the cause

| Why-did-this-render says | Likely cause |
|---|---|
| "Props changed: `onClick`" | New function identity each render |
| "Props changed: `config`" | New object literal each render |
| "Hook 1 changed" | Context or subscription changed |
| "Parent re-rendered" | Ancestor re-rendered; memo + stable props may help |

## Step 3: Fix the cause

### New function identity

```tsx
// Before
<Child onClick={() => save(id)} />

// After — only if Child is memoized
const handleClick = useCallback(() => save(id), [id]);
<Child onClick={handleClick} />
```

### New object literal

```tsx
// Before
<Child config={{ color: "red", size: 12 }} />

// After
const config = useMemo(() => ({ color: "red", size: 12 }), []);
<Child config={config} />
```

### Context thrash

```tsx
// Before — every provider update re-renders every consumer
<AppContext.Provider value={{ user, cart, theme }}>

// After — split by update frequency
<UserContext.Provider value={user}>
  <CartContext.Provider value={cart}>
    <ThemeContext.Provider value={theme}>
```

### Expensive render work

- Move pure computation to `useMemo` with real inputs.
- Move heavy work off the main thread (web worker).
- Or: render server-side if the output is derivable without user input.

### Large list

Virtualize.

```tsx
import { useVirtualizer } from "@tanstack/react-virtual";

const rowVirtualizer = useVirtualizer({
  count: items.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 48,
  overscan: 5,
});
```

## Step 4: Re-profile

If you can't see the win in the profiler, the change isn't one. Revert.

## Memoization — when it's worth it

`useMemo` / `useCallback` / `React.memo` add overhead. They pay off when:

1. The child is memoized and its props would otherwise be unstable.
2. The value is an expensive computation (heuristic: > 1 ms per call).
3. The value is a dependency of another hook.

Otherwise, skip. Prophylactic memoization makes code slower and harder
to read.

## Common wins, ranked

| Problem | Typical win |
|---|---|
| Unvirtualized list of 1000+ | 10–100× render time |
| Heavy computation in render | 2–10× render time |
| Unstable props to memoized child | Varies (can be 2–10×) |
| Unnecessary context re-renders | 1.5–5× for deep trees |
| `React.memo` on shallow children | Small — only worth it with real unstable parents |

## Code splitting

Route-level splitting is free performance:

```tsx
const Admin = React.lazy(() => import("./routes/Admin"));

<Suspense fallback={<Skeleton />}>
  <Admin />
</Suspense>
```

- Don't ship the admin bundle on the login page.
- Bundle analyzer (`rollup-plugin-visualizer`, `webpack-bundle-analyzer`)
  to find fat modules.

## SSR + Suspense streaming

For App Router / streaming SSR setups:

- Put slow subtrees behind Suspense — they stream independently.
- Keep the first meaningful paint "above the fold" synchronous;
  below-the-fold goes in Suspense.
- `revalidate` / `cache` directives keep server work out of the hot path.

## Render-avoidance patterns

### `React.memo` at a boundary

```tsx
const ExpensiveRow = React.memo(function Row({ item }) {
  return <Row item={item} />;
});
```

Pair with stable props. If the parent re-renders often but the row's
props don't change, memoization wins.

### Splitting state

```tsx
// Before — every keystroke re-renders children
const [state, setState] = useState({ name: "", email: "" });

// After — local per-field state, lift only what must be shared
```

### Pushing state down

Move state to the lowest component that needs it. Avoids re-rendering
siblings on every update.

## Anti-patterns

- `useMemo` around primitives (`useMemo(() => x * 2, [x])`) — costs more than it saves.
- `useCallback` on functions never passed to memoized children.
- `React.memo` with props containing new object literals each render — the memo check always fails.
- Perf work without profiling.
- Optimizing once, never re-checking after refactor.
