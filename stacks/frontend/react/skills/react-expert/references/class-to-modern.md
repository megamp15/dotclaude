---
source: stacks/react
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/react-expert/references/migration-class-to-modern.md
ported-at: 2026-04-17
adapted: true
---

# Class → modern migration

Migrate feature by feature. Do not do a big-bang rewrite.

## Concept mapping

| Class concept | Modern equivalent |
|---|---|
| `class Foo extends Component` | `function Foo(props)` |
| `this.state` | `useState` / `useReducer` |
| `this.setState({ x })` | `setX(x)` or `setState(prev => ({ ...prev, x }))` |
| `componentDidMount` | `useEffect(fn, [])` |
| `componentDidUpdate(prev)` | `useEffect(fn, [dep])` |
| `componentWillUnmount` | cleanup function returned from `useEffect` |
| `componentDidCatch` | ErrorBoundary (still class; wrap once, reuse) |
| `getDerivedStateFromProps` | derive in render / `useMemo` / `key` to reset |
| `getSnapshotBeforeUpdate` | `useLayoutEffect` to measure before paint |
| `shouldComponentUpdate` | `React.memo(Component, arePropsEqual?)` |
| Refs: `createRef` / callback refs | `useRef` / callback ref |
| `this.context` | `useContext(MyContext)` |
| `connect(mapState, mapDispatch)` | `useSelector` / `useDispatch` (or RTK Query) |
| HOCs (withRouter, withStyles, …) | hooks (useRouter, useStyles) |

## Worked example

### Before (class)

```tsx
class UserProfile extends React.Component {
  state = { user: null, loading: true, error: null };

  componentDidMount() {
    this.load();
  }

  componentDidUpdate(prev) {
    if (prev.userId !== this.props.userId) this.load();
  }

  load = async () => {
    this.setState({ loading: true, error: null });
    try {
      const user = await fetchUser(this.props.userId);
      this.setState({ user, loading: false });
    } catch (error) {
      this.setState({ error, loading: false });
    }
  };

  render() {
    const { user, loading, error } = this.state;
    if (loading) return <Skeleton />;
    if (error) return <ErrorMessage />;
    return <ProfileCard user={user} />;
  }
}
```

### After (TanStack Query)

```tsx
function UserProfile({ userId }: { userId: string }) {
  const { data: user, isLoading, error } = useQuery({
    queryKey: ["user", userId],
    queryFn: () => fetchUser(userId),
  });
  if (isLoading) return <Skeleton />;
  if (error) return <ErrorMessage />;
  return <ProfileCard user={user} />;
}
```

The mechanical port would use `useState` + `useEffect`, but TanStack
Query is usually the right endpoint for class components that loaded
data imperatively.

### After (mechanical, no TanStack)

```tsx
function UserProfile({ userId }: { userId: string }) {
  const [state, setState] = useState<
    | { status: "loading" }
    | { status: "ok"; user: User }
    | { status: "error" }
  >({ status: "loading" });

  useEffect(() => {
    const ctrl = new AbortController();
    setState({ status: "loading" });
    fetchUser(userId, { signal: ctrl.signal })
      .then((user) => setState({ status: "ok", user }))
      .catch((err) => {
        if (err.name !== "AbortError") setState({ status: "error" });
      });
    return () => ctrl.abort();
  }, [userId]);

  if (state.status === "loading") return <Skeleton />;
  if (state.status === "error") return <ErrorMessage />;
  return <ProfileCard user={state.user} />;
}
```

## Migration recipe

1. **Pick a leaf first.** Don't start at the top — start at a
   component with few descendants and clear props.
2. **Convert the class shape.** Turn `render()` into the function body;
   move JSX out.
3. **Map state.** One `useState` per logical slice, or `useReducer` when
   multiple fields transition together.
4. **Convert lifecycles.** `componentDidMount` + `componentDidUpdate` →
   one `useEffect` with the right dep array.
5. **Deal with `setState` callbacks.** Replace with a `useEffect` that
   watches the state slice.
6. **Replace HOCs with hooks.** `withRouter` → `useRouter`, etc.
7. **Convert class context consumer** → `useContext`.
8. **Convert `connect`** → `useSelector` + `useDispatch`, or RTK Query.
9. **Extract reusable pieces into custom hooks.**
10. **Replace `shouldComponentUpdate`.** In most cases, don't bother.
    If profiling shows a hot child, `React.memo` with an explicit
    `arePropsEqual`.
11. **ErrorBoundary.** `componentDidCatch` has no functional equivalent
    yet. Keep one ErrorBoundary class (or use `react-error-boundary`)
    and wrap the tree once.

## Things to watch

- **Stale closures.** After converting, every captured variable must be
  in the dep array — or intentionally captured by a ref.
- **Double fetch in dev.** `StrictMode` double-invokes effects in dev.
  Your effect must be idempotent (or have an `AbortController` cleanup).
- **Ref forwarding.** Class components that accepted a `ref` need
  `forwardRef`. React 19 allows ref as a regular prop for function
  components — prefer that where supported.
- **`defaultProps` on function components.** Use default values in the
  destructured parameter list instead.

## When NOT to migrate

- A class component is working, has tests, and no feature pressure.
- You don't have time for a full migration; a half-migration introduces
  two shapes of the same component.
- The class is an ErrorBoundary — that's still the idiomatic shape.

Migrate when you're already in the file for another reason, or when the
class shape blocks a feature.
