---
source: stacks/react
---

# Stack: React

React-specific conventions. Layers on top of `core/` and `stacks/node-ts`
(which should also be active for any TS-based React project). Read
those first; this file extends, it doesn't replace.

## Version assumption

Target **React 19+** (stable as of late 2024). Patterns that follow
assume modern React: function components + hooks, Server Components
where applicable, Suspense for async boundaries.

Legacy class components, `UNSAFE_componentWillMount`, and `connect()`-style Redux wrappers are out of scope. If the project is on React 17 or earlier, upgrade *then* apply these rules.

## Components

- **Function components, not classes.** Always.
- **Composition over inheritance.** Componentize by responsibility; pass `children` or slot props, not base-class inheritance.
- **Keep components pure** — given the same props + state, render the same output. Side effects go in `useEffect`, event handlers, or Server Actions.
- **Name by role, not shape.** `UserAvatar`, not `CircleImage`. Future-proofs against style changes.
- **File per component** for anything non-trivial (more than ~40 lines or more than one export). Small co-located pieces (`<ListItem>` used only inside `<List>`) can stay in the same file.
- **PascalCase** for components, **camelCase** for props and hook names. Hooks start with `use`.

## Hooks — rules that bite

- **Rules of hooks are non-negotiable**: top-level only, same order every render, only inside components or other hooks. The linter catches most violations — keep `eslint-plugin-react-hooks` on.
- **`useEffect` is an escape hatch, not a default.** If the work is "derive from props/state" → compute during render or `useMemo`. If it's "set state from props" → there's almost always a better pattern.
- **Dependencies arrays are not optional.** Never `// eslint-disable-line react-hooks/exhaustive-deps` — fix the real issue (missing deps, stale closures, unstable function identity).
- **`useCallback` / `useMemo` are not free.** They add overhead + deps tracking. Use them when (a) profiling shows a perf issue, (b) the value is passed to a memoized child that would otherwise re-render, or (c) the value is a dep of another hook. Otherwise skip.
- **`useState` for local state, `useReducer` for state with complex transitions.** When state updates depend on multiple pieces of prior state, reducer wins.

## State management — pick the smallest thing that works

- **Local state**: `useState` / `useReducer`.
- **Shared within a subtree**: lift state up or use `Context`. Context is fine for low-frequency updates (theme, user, locale). Not fine for frequently-changing values — every consumer re-renders.
- **App-wide, frequent updates**: **Zustand** is the modern lean default. Jotai for atomic, Redux Toolkit if the team already lives in Redux.
- **Server state**: **TanStack Query** (React Query) or **SWR**. Don't manage "data fetched from the server" with `useState` + `useEffect` — you'll reinvent caching, deduplication, revalidation, and all of it badly.
- **Form state**: `react-hook-form` is the default. Avoid hand-rolled form state for anything beyond 2-3 fields.

## Rendering strategies

- **Client components** by default when using Create React App / Vite / SPA setups.
- **Next.js App Router / React Server Components**: default is server; opt into client with `"use client"` when you need interactivity. Don't `"use client"` a whole page if only one leaf needs it — leaves stay server, only the interactive leaf goes client.
- **Suspense** for async boundaries. Pair with `ErrorBoundary` — Suspense handles loading, ErrorBoundary handles failure.

## Performance

- **Measure before optimizing.** React DevTools Profiler, not vibes. "Re-renders are slow" is usually wrong until proven.
- **`React.memo`** prevents re-render when props are shallow-equal. Only useful if the parent re-renders often *and* the memoized child is expensive *and* its props are stable.
- **Virtualize long lists** (TanStack Virtual, react-window). At 100+ items with meaningful per-item content, list virtualization is a dramatic win.
- **Code split** at route boundaries (`React.lazy` + Suspense). Don't ship the admin dashboard bundle to the login page.
- **Avoid `key={index}`** on lists that reorder, insert in the middle, or filter. Stable IDs only.

## Forms + accessibility

- Labels for every input (`<label htmlFor>` or `aria-label`).
- `type="submit"` on submit buttons; implicit submit on enter.
- Error text associated with inputs via `aria-describedby`.
- Disabled state during submission; prevent double-submit.
- Test with keyboard: can you tab through the form and submit without a mouse? If no, it's broken.

## Testing

- **Testing Library** (`@testing-library/react`) over Enzyme. Test behavior, not implementation.
- Query by accessible role/name: `screen.getByRole('button', { name: /save/i })` — if this fails, real screen readers also fail.
- Avoid `getByTestId` except as a last resort. `data-testid` is a crutch.
- `userEvent.type(input, 'foo')` > `fireEvent.change(input, {...})`. User-event simulates real interactions.
- Mock network at the HTTP layer (MSW), not by mocking every fetch call.

## Styling

Pick one and stick with it across the app:

- **Tailwind CSS** — utility-first; default recommendation for new projects in 2026.
- **CSS Modules** — scoped styles, zero runtime.
- **styled-components / emotion** — CSS-in-JS; watch bundle size + SSR cost.
- **Plain CSS** — fine for small apps.

Don't mix Tailwind with CSS-in-JS randomly. Consistency beats theoretical best.

## TypeScript specifics (also see stacks/node-ts)

- Props are typed. Prefer `type Props = { ... }` over `interface Props`.
- Default to `type` unless you need interface-specific features (declaration merging, `extends` in class hierarchies).
- Typing children: `children: React.ReactNode` for most cases.
- Refs: `useRef<HTMLDivElement>(null)` — generic + initial value.
- Event handlers: `(e: React.FormEvent<HTMLFormElement>) => void`, not bare `Event`.
- Don't use `React.FC` — implicit `children` typing is lossy; explicit is better.

## Do not

- Do not fetch data in `useEffect` when TanStack Query / SWR is available.
- Do not use `setState` to derive values you can compute during render.
- Do not mix controlled and uncontrolled inputs on the same field.
- Do not put non-serializable things (functions, class instances, Date objects) in state that needs to serialize (URL, localStorage, Redux).
- Do not reach into a child via refs to call imperative methods unless there's no prop-driven way. Refs-as-API is last resort.
- Do not render lists without stable `key`s.
