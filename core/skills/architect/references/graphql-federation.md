---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/graphql-architect/references/federation.md
ported-at: 2026-04-17
adapted: true
---

# Apollo Federation

Federation lets multiple subgraphs (owned by different teams) present a
single unified schema ("supergraph") to clients.

## When to federate

**Good reasons:**
- Multiple teams own distinct bounded contexts.
- Contexts are large enough that a single schema repo becomes a coordination bottleneck.
- You want the operational benefit of separate deploys while preserving a unified client experience.

**Bad reasons:**
- "Microservices are cool." Federation ≠ microservices.
- You have 3 engineers. You don't need federation; you need one schema.
- You want to "plan for scale". The coupling cost arrives on day 1; the benefit arrives later.

## Subgraph setup

```graphql
# users-subgraph/schema.graphql
extend schema
  @link(
    url: "https://specs.apollo.dev/federation/v2.5",
    import: ["@key", "@shareable"]
  )

type User @key(fields: "id") {
  id: ID!
  email: String!
  username: String!
  createdAt: DateTime!
}

type Query {
  user(id: ID!): User
  viewer: User
}
```

```ts
// users-subgraph/resolvers.ts
export const resolvers = {
  User: {
    __resolveReference: (ref: { id: string }, ctx) =>
      ctx.dataSources.users.findById(ref.id),
  },
  Query: {
    user: (_p, { id }, ctx) => ctx.dataSources.users.findById(id),
    viewer:  (_p, _a, ctx) => ctx.viewer,
  },
};

const server = new ApolloServer({
  schema: buildSubgraphSchema([{ typeDefs, resolvers }]),
});
```

## Entity keys

### Single key

```graphql
type Product @key(fields: "id") {
  id: ID!
  name: String!
  priceCents: Int!
}
```

### Composite key

```graphql
type Variant @key(fields: "productId sku") {
  productId: ID!
  sku: String!
  size: String!
  color: String!
}
```

### Multiple keys (different lookup shapes)

```graphql
type Review
  @key(fields: "id")
  @key(fields: "productId authorId") {
  id: ID!
  productId: ID!
  authorId: ID!
  rating: Int!
}
```

## Extending types across subgraphs

```graphql
# users-subgraph: owns User
type User @key(fields: "id") {
  id: ID!
  email: String!
  username: String!
}

# posts-subgraph: extends User with posts
type User @key(fields: "id") {
  id: ID!
  posts: [Post!]!
}

type Post @key(fields: "id") {
  id: ID!
  title: String!
  content: String!
  authorId: ID!
  author: User!
}
```

```ts
// posts-subgraph resolvers
export const resolvers = {
  User: {
    __resolveReference: (ref: { id: string }) => ({ id: ref.id }),
    posts: (u: { id: string }, _a, ctx) =>
      ctx.dataSources.posts.findByAuthor(u.id),
  },
  Post: {
    author: (p: Post) => ({ __typename: 'User', id: p.authorId }),
  },
};
```

## Federation directives (the ones you'll actually use)

| Directive | Purpose | Common use |
|---|---|---|
| `@key(fields: "…")` | Declare an entity key | Every entity |
| `@shareable` | Field can be resolved by multiple subgraphs | Value fields |
| `@external` | Field defined in another subgraph | Referenced keys only |
| `@requires(fields: "…")` | Resolver needs extra fields | Computed fields |
| `@provides(fields: "…")` | Hint that this subgraph can resolve extra fields | Optimization |
| `@override(from: "old-subgraph")` | Migrate a field between subgraphs | Migrations |
| `@inaccessible` | Hide from supergraph | Internal-only fields |
| `@tag(name: "…")` | Categorize for tooling | Contract APIs |

### `@provides` / `@requires` optimization

```graphql
type Post @key(fields: "id") {
  id: ID!
  authorId: ID!
  author: User! @provides(fields: "username")
}

type User @key(fields: "id") {
  id: ID! @external
  username: String! @external
}
```

Gateway can satisfy `post.author.username` without fetching from the user
subgraph if the post subgraph already has it.

## Gateway configuration

```ts
import { ApolloGateway, IntrospectAndCompose } from '@apollo/gateway';
import { ApolloServer } from '@apollo/server';

const gateway = new ApolloGateway({
  supergraphSdl: new IntrospectAndCompose({
    subgraphs: [
      { name: 'users',    url: process.env.USERS_SUBGRAPH_URL! },
      { name: 'posts',    url: process.env.POSTS_SUBGRAPH_URL! },
      { name: 'products', url: process.env.PRODUCTS_SUBGRAPH_URL! },
    ],
    pollIntervalInMs: 10_000,
  }),
  serviceHealthCheck: true,
  debug: process.env.NODE_ENV === 'development',
});

const server = new ApolloServer({
  gateway,
  async context({ req }) {
    return { token: req.headers.authorization ?? '' };
  },
});
```

**Production:** use managed federation (Apollo Studio / GraphOS). CI runs
subgraph checks against the current supergraph — bad schema changes fail
before deploying.

## Value types vs. entities

- **Entity**: has `@key`, can be extended by other subgraphs.
- **Value type**: no `@key`, resolved entirely by one subgraph.

```graphql
type Address {
  street: String!
  city: String!
  country: String!
}

type User @key(fields: "id") {
  id: ID!
  address: Address
}
```

Value types embedded in entities are fine and don't cross subgraph boundaries.

## Interface objects

For interfaces owned by one subgraph but referenced by others:

```graphql
# accounts-subgraph
interface Account {
  id: ID!
  email: String!
}
type User        implements Account @key(fields: "id") { ... }
type AdminUser   implements Account @key(fields: "id") { ... }

# orders-subgraph
type Account @key(fields: "id") @interfaceObject {
  id: ID!
}
type Order @key(fields: "id") {
  id: ID!
  account: Account!
}
```

## Migration between subgraphs

To move a field from subgraph A to subgraph B:

```graphql
# subgraph B (new owner)
type Product @key(fields: "id") {
  id: ID!
  priceCents: Int! @override(from: "legacy")
}
```

1. Add the field in B with `@override`.
2. Deploy B — gateway routes reads to B.
3. Remove the field from A.
4. Remove `@override` (optional cleanup).

## Error handling in references

```ts
export const resolvers = {
  User: {
    __resolveReference: async (ref: { id: string }, ctx) => {
      try {
        const u = await ctx.dataSources.users.findById(ref.id);
        return u ?? null; // soft error: entity not found
      } catch (err: any) {
        throw new GraphQLError('Failed to resolve user', {
          extensions: { code: 'USER_RESOLUTION_FAILED', userId: ref.id },
        });
      }
    },
  },
};
```

## Rules

- Every entity has `@key`. Design keys before writing resolvers.
- Subgraphs align to team ownership boundaries, not technical layers.
- Shared primitives are value types, not entities.
- Use `@override` for migrations; never dual-own a field long-term.
- Run supergraph composition checks in CI before every subgraph deploy.
- Monitor query-plan performance — federation can make simple queries expensive.
- Document entity ownership and extension points (this is the real "API" between teams).
