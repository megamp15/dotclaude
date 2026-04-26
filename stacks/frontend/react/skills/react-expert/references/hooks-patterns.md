---
source: stacks/react
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/react-expert/references/hooks-patterns.md
ported-at: 2026-04-17
adapted: true
---

# Hooks — design + testing

Most production React code lives in hooks. Design them like small APIs.

## Anatomy of a good custom hook

```tsx
function useDebouncedValue<T>(value: T, delayMs: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs);
    return () => clearTimeout(id);
  }, [value, delayMs]);
  return debounced;
}
```

Checklist:
- Name starts with `use`.
- Inputs are explicit and typed.
- Output is stable in shape — consumers destructure safely.
- Effect has a cleanup function.
- No side effects at call time (outside effects).

## Patterns

### Data loader

```tsx
function useItem(id: string | null) {
  const [state, setState] = useState<
    | { status: "idle" }
    | { status: "loading" }
    | { status: "ok"; data: Item }
    | { status: "error"; error: Error }
  >({ status: "idle" });

  useEffect(() => {
    if (id === null) return;
    const ctrl = new AbortController();
    setState({ status: "loading" });
    fetch(`/api/items/${id}`, { signal: ctrl.signal })
      .then((r) => (r.ok ? r.json() : Promise.reject(r)))
      .then((data: Item) => setState({ status: "ok", data }))
      .catch((error: unknown) => {
        if ((error as Error).name !== "AbortError") {
          setState({ status: "error", error: error as Error });
        }
      });
    return () => ctrl.abort();
  }, [id]);

  return state;
}
```

Better: use TanStack Query or SWR. Only hand-roll when you're the library.

### Controlled + uncontrolled

```tsx
function useControllableState<T>(
  controlled: T | undefined,
  defaultValue: T,
  onChange?: (v: T) => void,
): [T, (v: T) => void] {
  const [internal, setInternal] = useState(defaultValue);
  const isControlled = controlled !== undefined;
  const value = isControlled ? (controlled as T) : internal;
  const setValue = (v: T) => {
    if (!isControlled) setInternal(v);
    onChange?.(v);
  };
  return [value, setValue];
}
```

Lets a component be used either controlled or uncontrolled — common in
design systems.

### Stable callback (reads latest state)

```tsx
function useEvent<Args extends unknown[], R>(
  handler: (...args: Args) => R,
): (...args: Args) => R {
  const ref = useRef(handler);
  useLayoutEffect(() => {
    ref.current = handler;
  });
  return useCallback((...args: Args) => ref.current(...args), []) as (
    ...args: Args
  ) => R;
}
```

Useful when passing a callback to a long-lived subscription that mustn't
re-bind on every render. Don't over-use — prefer `useCallback` +
dependencies when you can.

### Media query

```tsx
function useMediaQuery(query: string): boolean {
  const subscribe = useCallback(
    (cb: () => void) => {
      const mql = window.matchMedia(query);
      mql.addEventListener("change", cb);
      return () => mql.removeEventListener("change", cb);
    },
    [query],
  );
  const snapshot = useCallback(() => window.matchMedia(query).matches, [query]);
  return useSyncExternalStore(subscribe, snapshot, () => false);
}
```

`useSyncExternalStore` is the correct primitive for subscribing to
browser APIs — it handles concurrent rendering correctly.

## Pitfalls

### Stale closures

```tsx
useEffect(() => {
  const id = setInterval(() => {
    console.log(count); // captures count at effect creation
  }, 1000);
  return () => clearInterval(id);
}, []); // ← missing `count` dep
```

Fixes: include `count` in deps (and re-subscribe), or use a ref:

```tsx
const countRef = useRef(count);
useLayoutEffect(() => { countRef.current = count; });
```

### Unstable function identity

```tsx
<Child onSave={(v) => save(v)} />   // new fn every render
```

If `Child` is memoized, the memoization never wins. Wrap in `useCallback`
or hoist the function.

### Effects as state-sync

If the effect exists only to set state based on other state/props, you
have derived state, not an effect. Compute in render or `useMemo`.

### Missing cleanup

Every subscription, timer, event listener, or mutation you can't undo
declaratively needs a cleanup.

### Hooks inside conditionals / loops

The order of hook calls must be the same on every render. Lint catches
this — keep `eslint-plugin-react-hooks` on.

## Testing custom hooks

Use `renderHook` from `@testing-library/react`.

```tsx
import { renderHook, act } from "@testing-library/react";
import { useCounter } from "./useCounter";

test("increments", () => {
  const { result } = renderHook(() => useCounter(0));
  act(() => result.current.increment());
  expect(result.current.value).toBe(1);
});
```

- Wrap state changes in `act()`.
- For hooks needing a Provider, pass `{ wrapper: MyProvider }`.
- For hooks that read `window.matchMedia` or other browser APIs, mock
  them on the test setup — or run in `jsdom`.

## Organization

- `hooks/useX.ts` per hook; colocate tests.
- Export only the hook. Avoid exporting internal helpers from the hook
  file.
- Document: inputs, outputs, lifecycle, and any gotchas about memoization.
