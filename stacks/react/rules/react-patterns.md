---
source: stacks/react
name: react-patterns
description: React-specific patterns and anti-patterns that aren't covered by general TS/JS style or universal code-quality rules. Load when writing or reviewing React components, hooks, or state logic.
triggers: react, useEffect, useState, useMemo, useCallback, jsx, tsx, component, hook, props, context, reducer, suspense, server component, rsc, client component
globs: ["**/*.tsx", "**/*.jsx", "**/components/**/*.ts", "**/hooks/**/*.ts"]
---

# React patterns and anti-patterns

The subset of React conventions worth enforcing as rules (vs. taste).

## When to reach for what (state)

```
Is the state derived from other state / props?
  └─ Yes → compute in render, or useMemo. Do not useState.
  └─ No → is it local to one component?
            └─ Yes → useState
            └─ No → is it server data (fetched)?
                      └─ Yes → TanStack Query / SWR
                      └─ No → is it shared across a subtree?
                                └─ Yes → lift state up, or Context (low-frequency), or Zustand (high-frequency)
                                └─ No → you probably have a scoping problem, re-check
```

## Common anti-patterns

### `useState` + `useEffect` to derive from props

```tsx
// BAD
function Price({ amount, currency }) {
  const [formatted, setFormatted] = useState('');
  useEffect(() => {
    setFormatted(new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount));
  }, [amount, currency]);
  return <span>{formatted}</span>;
}

// GOOD
function Price({ amount, currency }) {
  const formatted = useMemo(
    () => new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount),
    [amount, currency]
  );
  return <span>{formatted}</span>;
}

// EVEN BETTER — it's not expensive enough for useMemo
function Price({ amount, currency }) {
  const formatted = new Intl.NumberFormat(undefined, { style: 'currency', currency }).format(amount);
  return <span>{formatted}</span>;
}
```

The `useState`+`useEffect` version has: stale first render, wasted re-render, double-work. The inline compute has none of these.

### `useEffect` to sync two states

```tsx
// BAD
const [selected, setSelected] = useState(null);
const [selectedDetails, setSelectedDetails] = useState(null);
useEffect(() => {
  if (selected) fetchDetails(selected).then(setSelectedDetails);
}, [selected]);

// GOOD
const { data: details } = useQuery({
  queryKey: ['details', selected],
  queryFn: () => fetchDetails(selected),
  enabled: !!selected,
});
```

TanStack Query handles caching, loading state, error state, and stale-while-revalidate. Hand-rolled version reinvents all of it badly.

### Re-derived context causing cascading re-renders

```tsx
// BAD — new object on every render; every consumer re-renders
<UserContext.Provider value={{ user, updateUser }}>
  ...
</UserContext.Provider>

// GOOD — stable identity
const contextValue = useMemo(() => ({ user, updateUser }), [user, updateUser]);
<UserContext.Provider value={contextValue}>
  ...
</UserContext.Provider>
```

Or split: one context for the value (changes often), one for the setter (stable).

### `key={index}` on dynamic lists

```tsx
// BAD — list reorders, React mis-reuses DOM nodes
items.map((item, i) => <Row key={i} item={item} />)

// GOOD
items.map(item => <Row key={item.id} item={item} />)
```

`key={index}` is fine for truly static lists that never reorder/filter/insert. Otherwise stable IDs.

### Prop drilling when Context would do

Five levels of `userName` passed through components that don't use it: use Context (or Zustand). Rule of thumb: if the same prop passes through 3+ levels untouched, it belongs in shared state.

### Context for everything

The opposite mistake. Context on every shared value = whole-tree re-renders. Split contexts by update frequency, or move frequently-changing state to Zustand/Jotai.

### Derived state with `getDerivedStateFromProps`-style hacks

```tsx
// BAD — "the props changed, reset internal state"
useEffect(() => { setDraft(initialValue) }, [initialValue]);

// GOOD — use key to remount
<EditorForm key={itemId} initialValue={initialValue} />
```

Keying to remount is a legitimate pattern for "reset everything when X changes."

### Conditional hooks

```tsx
// BAD
if (user) {
  const [name, setName] = useState(user.name);  // illegal
}

// GOOD
const [name, setName] = useState(user?.name ?? '');
```

Hooks must run in the same order every render. Always.

## Suspense + data loading

React 19's Suspense integration with data libs (TanStack Query v5 `suspense: true`, Relay, Next.js data fetching) means loading states can be declarative:

```tsx
<Suspense fallback={<Skeleton />}>
  <ErrorBoundary fallback={<ErrorMessage />}>
    <UserProfile userId={userId} />
  </ErrorBoundary>
</Suspense>
```

`<UserProfile>` reads data via a Suspense-compatible hook; the tree handles loading + error without explicit `if (loading)` / `if (error)` branches in every component.

**Pair Suspense with ErrorBoundary.** Suspense handles "loading"; ErrorBoundary handles "failed." Either without the other is incomplete.

## Server Components (Next.js App Router)

- Default to server. Opt into client with `"use client"` directive.
- Server components can be `async` — top-level await works.
- Props to a client component must be serializable. Functions can't cross the boundary (use Server Actions for mutations).
- Client component can render a server component passed as `children`, not imported directly.
- Don't `"use client"` a whole page for one interactive leaf — leaf the leaf.

Common misstep: putting `"use client"` at the top of a layout "just to be safe." This cascades — every descendant becomes a client component. Be intentional about the boundary.

## Performance checklist

Before optimizing, **profile**:

1. Open React DevTools Profiler; record an interaction.
2. Look for unexpected re-renders (flame graph shows you which).
3. Figure out *why* the re-render happens: new prop identity, parent re-rendered, context value changed.
4. Fix the cause (stabilize identity, split context, memo if necessary).

Don't sprinkle `useMemo` / `useCallback` / `React.memo` prophylactically. Each adds overhead; only pays off when a known-expensive child would otherwise re-render.

## Accessibility as a first-class concern

- Semantic HTML first: `<button>`, `<a href>`, `<form>`, `<label>`, `<input type="submit">`.
- ARIA only when semantic HTML can't express it.
- Keyboard navigation: every interactive element must be reachable and usable via keyboard.
- Focus management after route changes and modal opens.
- Test with `axe` / `@axe-core/react` in dev mode. CI fail on new violations.

A React app that fails keyboard navigation or screen reader use is broken, not just suboptimal.
