---
name: graphql-architect
description: Design GraphQL schemas, resolvers, Apollo Federation subgraphs, real-time subscriptions, and query performance. Use when designing a GraphQL API, reviewing schema decisions, resolving N+1 problems, or federating subgraphs. For REST, use api-designer.
source: core
triggers: /graphql-architect, GraphQL, schema design, Apollo, Apollo Federation, subgraph, resolver, DataLoader, N+1, GraphQL subscription, supergraph
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/graphql-architect
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# graphql-architect

You design GraphQL schemas that stay legible at scale. Types are intentional,
resolvers are batched with DataLoader, federation boundaries match team
boundaries, and authorization is not an afterthought.

## When this skill is the right tool

- Designing a new GraphQL schema
- Reviewing an existing schema for consistency and performance
- Resolving N+1 query explosions
- Designing Apollo Federation subgraphs and entity keys
- Adding subscriptions / real-time updates
- Planning query-complexity limits and security posture

**Not for:**
- REST API design → `api-designer`
- System architecture → `architecture-designer`
- Generic backend plumbing → language stack rules

## Core workflow

1. **Model the domain** — start with types and fields, not queries.
2. **Design queries** — shape them around UI needs, not DB tables.
3. **Design mutations** — input types, payload types, clear errors.
4. **Pick subscription scope** — only where real-time genuinely helps.
5. **Plan resolvers** — DataLoader for every foreign-key edge.
6. **Authorize at the resolver** — not at the gateway.
7. **Limit complexity** — depth, breadth, and query-cost ceilings.
8. **Decide federation** — monolith schema vs. subgraphs aligned to teams.

## Schema design

### Types

```graphql
"""A registered user."""
type User {
  id: ID!
  email: EmailAddress!
  username: String!
  createdAt: DateTime!
  posts(first: Int = 10, after: String): PostConnection!
}

"""A blog post."""
type Post {
  id: ID!
  title: String!
  content: String!
  author: User!
  publishedAt: DateTime
  status: PostStatus!
}

enum PostStatus { DRAFT PUBLISHED ARCHIVED }

scalar DateTime
scalar EmailAddress
```

**Rules:**
- PascalCase for types, camelCase for fields, SCREAMING_SNAKE for enum values.
- Every user-visible type has a description; avoid "just a wrapper" types.
- Nullable by default (`String`), non-null (`!`) only when you truly mean "this will never be null".
- Non-null lists: `[Post!]!` is a non-null list of non-null items.

### Input types

```graphql
input CreatePostInput {
  title: String!
  content: String!
  tags: [String!] = []
}
```

One input per mutation; no reusing input types across mutations (they diverge fast).

### Connections (pagination)

```graphql
type PostConnection {
  edges: [PostEdge!]!
  pageInfo: PageInfo!
  totalCount: Int
}
type PostEdge {
  node: Post!
  cursor: String!
}
type PageInfo {
  hasNextPage: Boolean!
  hasPreviousPage: Boolean!
  startCursor: String
  endCursor: String
}
```

Cursor-based by default. `totalCount` is optional and usually expensive.

### Errors in mutations

Use a payload type per mutation with a `userErrors` field — don't throw for
expected business errors:

```graphql
type CreatePostPayload {
  post: Post
  userErrors: [UserError!]!
}
type UserError {
  message: String!
  field: [String!]
  code: UserErrorCode!
}
enum UserErrorCode {
  VALIDATION_FAILED
  NOT_AUTHORIZED
  CONFLICT
  INTERNAL
}
```

Transport errors (500s, auth failures, malformed queries) stay in `errors[]`.
Domain errors go in `userErrors`. See the Shopify API for this pattern.

## Resolvers: batch everything

N+1 is the single biggest GraphQL performance problem. Solve it once, with
DataLoader, for every edge.

```ts
import DataLoader from 'dataloader';

export function createLoaders(db: DB) {
  return {
    userById: new DataLoader<string, User | null>(async (ids) => {
      const rows = await db.user.findMany({ where: { id: { in: [...ids] } } });
      const byId = new Map(rows.map(r => [r.id, r]));
      return ids.map(id => byId.get(id) ?? null);
    }),

    postsByAuthor: new DataLoader<string, Post[]>(async (authorIds) => {
      const rows = await db.post.findMany({
        where: { authorId: { in: [...authorIds] } },
        orderBy: { createdAt: 'desc' },
      });
      const grouped = new Map<string, Post[]>();
      for (const p of rows) {
        (grouped.get(p.authorId) ?? grouped.set(p.authorId, []).get(p.authorId)!).push(p);
      }
      return authorIds.map(id => grouped.get(id) ?? []);
    }),
  };
}

// In resolver
export const resolvers = {
  Post: {
    author: (post, _args, ctx) => ctx.loaders.userById.load(post.authorId),
  },
  User: {
    posts: (user, _args, ctx) => ctx.loaders.postsByAuthor.load(user.id),
  },
};
```

**Rules:**
- Create loaders **per request**, never at module scope — cross-request cache is a leak + bug.
- Preserve input order in batch functions (DataLoader relies on it).
- Use loaders for every foreign-key edge. No exceptions.

See `references/resolvers.md` for error handling, context, and pagination
resolvers.

## Authorization

Authorize at the **resolver boundary**, not at the gateway. The gateway
doesn't know which fields in a query touch which authorization scopes.

```ts
export const resolvers = {
  Query: {
    adminUsers: (_p, _a, ctx) => {
      if (!ctx.viewer?.isAdmin) throw new ForbiddenError('ADMIN_ONLY');
      return ctx.dataSources.users.findAll();
    },
  },
  User: {
    email: (user, _a, ctx) => {
      if (ctx.viewer?.id !== user.id && !ctx.viewer?.isAdmin) return null;
      return user.email;
    },
  },
};
```

Prefer field-level nulls to resolver-level throws for "the caller just can't
see this particular field". Throw when access itself is the error.

## Query complexity and rate limiting

Public GraphQL endpoints are targets for complexity attacks. Enforce:

- **Max depth** (e.g., 10).
- **Max breadth** per field (e.g., list sizes ≤ 100).
- **Query cost scoring** — assign a cost per field, reject above a budget.
  Libraries: `graphql-query-complexity`, `graphql-shield`.
- **Persisted queries** for known clients — only accept SHA256-identified queries.
- **Rate limits** per operation, per user.
- **Timeouts** on resolvers.

## Federation (Apollo)

Use when multiple teams own distinct bounded contexts but want to present a
unified graph to clients. See `references/federation.md` for keys,
`@shareable`, `@requires`, `@provides`, migration patterns.

**Rules:**
- Each subgraph owns its entities (`@key`) and the fields it resolves.
- Shared primitives (IDs, enums) are value types, not entities.
- Use `@interfaceObject` to extend interface types without knowing all implementations.
- Schema composition runs in CI before every subgraph deploy.
- Managed federation (Apollo Studio) for production — subgraph checks block bad pushes.

## Subscriptions

Use real-time only when it's a real requirement:
- Live collaboration (docs, whiteboards)
- Dashboards where polling is too expensive
- Chat, presence, notifications

```graphql
type Subscription {
  messageAdded(channelId: ID!): Message!
  orderStatusChanged(orderId: ID!): Order!
}
```

**Rules:**
- Authorize on subscribe **and** on every event emission (permissions can change mid-subscription).
- Use `graphql-ws` (not the deprecated `subscriptions-transport-ws`).
- Scale with Redis pub/sub, Kafka, or a purpose-built broker — not in-process event emitters.
- Publish event schemas; payload shape changes are breaking.

## Must do

- DataLoader for every foreign-key edge, scoped per request.
- Authorize in resolvers; use field-level nulls for "can't see this".
- Connection/pageInfo pattern for pagination.
- Mutation payloads with `userErrors` for expected failures.
- Enforce depth, breadth, cost, and timeouts.
- Persisted queries for known public clients.
- One schema owner per field; federation subgraphs align to teams.

## Must not do

- Share DataLoader instances across requests.
- Mirror the SQL schema 1:1 — shape by UI needs.
- Throw for expected domain errors; return `userErrors`.
- Skip `@key` design upfront in federation — retrofitting keys is painful.
- Run an open GraphQL endpoint with no complexity limits on a public API.
- Use subscriptions for "fancy polling" — poll from the client if it works.

## Output template

```markdown
# GraphQL schema: <name>

## Types
<SDL excerpt>

## Resolvers
| Field | Data source | DataLoader | Auth |
|---|---|---|---|

## Pagination
Connections with cursor; default page size 20, max 100.

## Errors
- Domain errors: UserError payloads
- Transport errors: standard errors[]

## Complexity
- Max depth: 10
- Max breadth per list: 100
- Cost budget: 1000 per query

## Federation
- Subgraph ownership: <team → types>
- Entity keys: <list>
```

## References

| Topic | File |
|---|---|
| Resolver patterns, context, DataLoader, pagination, errors | `references/resolvers.md` |
| Apollo Federation — keys, directives, composition | `references/federation.md` |
| Subscriptions, security hardening, complexity controls | `references/subscriptions-and-security.md` |
