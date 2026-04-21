---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/code-documenter/references/typescript-jsdoc.md
ported-at: 2026-04-17
adapted: true
---

# TypeScript JSDoc

TypeScript already carries most of the type information, so JSDoc focuses
on **intent, errors, side effects, and examples** — not restating types.

## Functions

```typescript
/**
 * Fetch a paginated list of products.
 *
 * @param categoryId - Category to filter by.
 * @param page - Page number, 1-indexed. Defaults to 1.
 * @param limit - Max items per page. Defaults to 20.
 * @returns Page of product records.
 * @throws {NotFoundError} If the category does not exist.
 * @throws {RateLimitError} If the caller is over the per-minute cap.
 *
 * @example
 * const page = await fetchProducts("electronics", 2, 10);
 * console.log(page.items[0].sku);
 */
export async function fetchProducts(
  categoryId: string,
  page = 1,
  limit = 20,
): Promise<ProductPage> { /* … */ }
```

### Rules

- Do **not** repeat `{TypeName}` for params that already have TS types.
- Always document `@throws` for the public contract.
- Use `@example` for anything non-obvious.
- Use `@deprecated <reason and replacement>` when deprecating.

## Classes

```typescript
/**
 * Token-bucket rate limiter, Redis-backed for distributed use.
 *
 * @example
 * const limiter = new RateLimiter({ rate: 10, burst: 100 });
 * if (await limiter.allow("user:42")) { ... }
 */
export class RateLimiter {
  /**
   * @param opts - Rate and burst configuration.
   */
  constructor(opts: RateLimiterOptions) { /* … */ }

  /**
   * Attempt to consume a token for `key`.
   *
   * @param key - Stable identity for the caller (e.g. user ID).
   * @returns `true` if the operation is allowed, otherwise `false`.
   */
  async allow(key: string): Promise<boolean> { /* … */ }
}
```

## Types and interfaces

```typescript
/**
 * Pagination cursor used by list endpoints.
 *
 * Opaque to clients; round-tripped unchanged.
 */
export interface PaginationCursor {
  /** Base64url-encoded server state. */
  token: string;
  /** Page size the client requested. */
  limit: number;
}
```

## React components

```typescript
/**
 * Button for primary call-to-action surfaces.
 *
 * Accessible: uses semantic `<button>` and forwards `aria-*` props.
 *
 * @example
 * <CTAButton onClick={submit}>Save</CTAButton>
 */
export function CTAButton(props: CTAButtonProps) { /* … */ }

interface CTAButtonProps {
  /** Visible label. */
  children: React.ReactNode;
  /** Click handler. */
  onClick: () => void;
  /** Disables and announces to assistive tech. */
  disabled?: boolean;
}
```

Prefer documenting the **props interface** field-by-field over re-documenting
each field in the JSDoc block — IDEs surface those on hover.

## Modules

```typescript
/**
 * @packageDocumentation
 * Orders domain — pricing, stock checks, and lifecycle transitions.
 *
 * Do not import infra modules from here.
 */
```

## Useful tags

| Tag | Use |
|---|---|
| `@param name - desc` | Parameter description |
| `@returns desc` | Return value description |
| `@throws {Type} desc` | Documented error |
| `@example` | Runnable usage example |
| `@deprecated reason` | Deprecated symbol + replacement |
| `@see` | Link to related symbol/doc |
| `@internal` | Hide from generated docs |
| `@remarks` | Extended discussion |
| `@packageDocumentation` | Module-level overview |

## Validation

- `tsc --noEmit` — confirms `@example` snippets in `.ts` files type-check.
- ESLint plugin `eslint-plugin-jsdoc` — enforces presence/shape rules.
- TypeDoc — generate a docs site from the JSDoc to spot gaps.

## Common mistakes

- Duplicating type information already in the signature.
- Missing `@throws` / `@deprecated` on public APIs.
- Example snippets that don't compile (validate them).
- Over-documenting private helpers or trivial utilities.
- Mixing JSDoc with TSDoc syntax inconsistently — pick one renderer and
  follow its rules.
