---
name: code-documenter
description: Add or refresh inline documentation — docstrings, JSDoc, OpenAPI specs, doc-site scaffolding, and user guides. Detects language and framework, picks a consistent format, validates examples, and reports coverage. Distinct from spec-miner (reverse-engineering behavior) and explain (one-off walkthroughs).
source: core
triggers: /document, /docs, add docstrings, generate docstrings, JSDoc, OpenAPI, Swagger, API documentation, doc site, user guide, documentation coverage
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/code-documenter
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# code-documenter

You add documentation that a future maintainer can actually trust:
- consistent format (picked up front, never mixed)
- framework-aware API docs (not a generic OpenAPI skeleton)
- validated examples (compile/run before claiming "documented")
- explicit error and side-effect documentation
- a coverage report at the end

## When this skill is the right tool

- Adding docstrings / JSDoc to an undocumented module
- Generating or refreshing an OpenAPI / Swagger spec
- Scaffolding a docs site (Docusaurus, MkDocs, VitePress)
- Writing a getting-started guide or tutorial
- Producing a coverage report for public APIs

**Not for:**
- Reverse-engineering behavior → `spec-miner`
- One-off "explain this code" walkthroughs → `explain`
- Generating a feature spec → `feature-forge`

## Core workflow

1. **Discover.** Confirm with the user:
   - Format preference (Google / NumPy / Sphinx for Python; JSDoc for TS; …).
   - Scope (public API only vs. all, single module vs. whole repo).
   - Exclusions (generated code, vendored, experiments).
2. **Detect.** Identify language(s), framework(s), and existing conventions.
   Match the house style if one already exists.
3. **Analyze.** Find undocumented public surface. Prioritize:
   - Public exports, API handlers, classes, and important types.
   - Functions with non-obvious side effects or error behavior.
4. **Document.** Apply the chosen format consistently. Include:
   - Purpose (what + why, not restating the signature).
   - Params + types.
   - Return shape.
   - Errors / exceptions / status codes.
   - Side effects (I/O, events, cache).
   - A runnable example for non-trivial APIs.
5. **Validate.** Don't ship broken examples:
   - Python doctests: `python -m doctest <file>` or `pytest --doctest-modules`.
   - TypeScript: `tsc --noEmit` on example files.
   - OpenAPI: `npx @redocly/cli lint openapi.yaml` (or `spectral lint`).
   - Fix failures and re-run before the report step.
6. **Report.** Produce a coverage summary (see below).

## Quick-reference examples

### Google-style docstring (Python)

```python
def fetch_user(user_id: int, active_only: bool = True) -> dict:
    """Fetch a single user record by ID.

    Args:
        user_id: Unique identifier for the user.
        active_only: When True, raise if the user is inactive.

    Returns:
        dict with keys `id`, `name`, `email`, `created_at`.

    Raises:
        ValueError: If `user_id` is not a positive integer.
        UserNotFoundError: If no matching user exists.
    """
```

### NumPy-style docstring (Python)

```python
def compute_similarity(vec_a: np.ndarray, vec_b: np.ndarray) -> float:
    """Compute cosine similarity between two vectors.

    Parameters
    ----------
    vec_a : np.ndarray
        First input vector, shape (n,).
    vec_b : np.ndarray
        Second input vector, shape (n,).

    Returns
    -------
    float
        Cosine similarity in [-1, 1].

    Raises
    ------
    ValueError
        If vectors have different lengths.
    """
```

### JSDoc (TypeScript)

```typescript
/**
 * Fetch a paginated list of products.
 *
 * @param categoryId - Category to filter by.
 * @param page - Page number (1-indexed). Defaults to 1.
 * @param limit - Max items per page. Defaults to 20.
 * @returns Page of product records.
 * @throws {NotFoundError} If the category does not exist.
 *
 * @example
 * const page = await fetchProducts("electronics", 2, 10);
 * console.log(page.items);
 */
async function fetchProducts(
  categoryId: string,
  page = 1,
  limit = 20
): Promise<ProductPage> { /* … */ }
```

### OpenAPI operation

```yaml
paths:
  /orders:
    post:
      operationId: createOrder
      summary: Create a new order.
      tags: [Orders]
      security:
        - bearerAuth: []
      requestBody:
        required: true
        content:
          application/json:
            schema: { $ref: "#/components/schemas/CreateOrderRequest" }
      responses:
        "201": { description: Created, content: { application/json: { schema: { $ref: "#/components/schemas/Order" } } } }
        "400": { $ref: "#/components/responses/ValidationError" }
        "401": { $ref: "#/components/responses/Unauthorized" }
        "409": { $ref: "#/components/responses/Conflict" }
```

## Coverage report

At the end, emit a concise coverage table.

```markdown
## Documentation coverage

| Module | Public symbols | Documented | % |
|---|---:|---:|---:|
| src/api/orders | 12 | 12 | 100% |
| src/domain/orders | 22 | 20 | 91% |
| src/infra/db | 8 | 4 | 50% |
| **Total** | **42** | **36** | **86%** |

Gaps:
- `src/infra/db.retry_policy` — undocumented public fn.
- `src/domain/orders.cancel_reason` — missing `Raises:` section.
```

Flag:
- Public symbols missing docs.
- Docs missing parameters / returns / errors sections.
- Examples that failed validation.
- Dead or internal-only APIs that are marked public (suggest moving to `_internal`).

## Rules

### Must do

- Ask for format preference before starting (don't guess).
- Use one style per language across the repo.
- Document all **public** functions, classes, methods, and types.
- Document parameters, return shapes, errors, and notable side effects.
- Test every code example in the docs.
- Produce a coverage summary.
- For REST APIs: fill in `operationId`, `tags`, error responses, auth.

### Must not

- Mix docstring styles in the same project.
- Rewrite working docs just to change style (unless asked).
- Document trivial getters/setters verbosely.
- Claim "documented" for code with failing examples.
- Treat OpenAPI/JSDoc as the business spec — that's spec-miner's job.
- Add AI-generated filler ("this function performs the function") — if the
  docstring isn't more informative than the signature, leave it out.

## References

| Topic | File |
|---|---|
| Python docstrings — Google/NumPy/Sphinx styles | `references/python-docstrings.md` |
| TypeScript JSDoc patterns | `references/typescript-jsdoc.md` |
| FastAPI / Django API docs | `references/api-docs-python.md` |
| Node.js (NestJS / Express) API docs | `references/api-docs-node.md` |
| Doc site systems (Docusaurus, MkDocs, VitePress) | `references/doc-systems.md` |
| Coverage report patterns | `references/coverage-reports.md` |
