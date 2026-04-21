---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/graphql-architect/references/resolvers.md
ported-at: 2026-04-17
adapted: true
---

# GraphQL resolvers

## Resolver signature

```ts
type Resolver<Source, Args, Context, Return> = (
  parent: Source,
  args: Args,
  context: Context,
  info: GraphQLResolveInfo,
) => Return | Promise<Return>;
```

## Context setup

```ts
export interface Context {
  viewer: User | null;
  dataSources: DataSources;
  loaders: Loaders;
  req: Request;
  requestId: string;
}

const server = new ApolloServer<Context>({
  schema,
  async context({ req }) {
    const token = req.headers.authorization?.replace('Bearer ', '') ?? null;
    const viewer = token ? await verifyToken(token) : null;
    const dataSources = createDataSources(db, redis);
    const loaders = createLoaders(dataSources);
    return {
      viewer,
      dataSources,
      loaders,
      req,
      requestId: req.headers['x-correlation-id'] as string ?? crypto.randomUUID(),
    };
  },
});
```

Rules:
- `loaders` are per-request (never module-scoped).
- Context creation is fast; expensive work happens inside resolvers.
- Include a `requestId` / correlation ID — log with it.

## DataLoader (N+1 prevention)

```ts
import DataLoader from 'dataloader';

export function createLoaders(ds: DataSources): Loaders {
  return {
    userById: new DataLoader<string, User | null>(async (ids) => {
      const users = await ds.users.findByIds([...ids]);
      const byId = new Map(users.map(u => [u.id, u]));
      return ids.map(id => byId.get(id) ?? null);
    }),

    postsByAuthor: new DataLoader<string, Post[]>(async (authorIds) => {
      const posts = await ds.posts.findByAuthorIds([...authorIds]);
      return authorIds.map(id => posts.filter(p => p.authorId === id));
    }),
  };
}
```

**Invariants:**
- Return the same length as input, in the same order.
- Return `null` (not `undefined`) for missing items.
- Keep batch size reasonable (`maxBatchSize: 100–1000`).

## Field resolvers

```ts
export const resolvers = {
  User: {
    fullName: (u: User) => `${u.firstName} ${u.lastName}`,

    postCount: (u: User, _args, ctx: Context) =>
      ctx.dataSources.posts.countByAuthor(u.id),

    posts: (u: User, args: { first?: number; status?: PostStatus }, ctx: Context) =>
      ctx.dataSources.posts.findByAuthor(u.id, {
        limit: args.first ?? 10,
        status: args.status,
      }),
  },
};
```

**Guidance:**
- Cheap derivations (concatenation, formatting) are fine as sync resolvers.
- Any I/O in a field resolver → use DataLoader.

## Pagination resolver (connections)

```ts
import { encodeCursor, decodeCursor } from '../utils/cursor';

const resolvers = {
  Query: {
    async posts(
      _p,
      args: { first?: number; after?: string },
      ctx: Context,
    ): Promise<PostConnection> {
      const limit = Math.min(args.first ?? 20, 100);
      const cursor = args.after ? decodeCursor(args.after) : null;

      // fetch limit+1 so we can compute hasNextPage without another query
      const rows = await ctx.dataSources.posts.findAll({ limit: limit + 1, cursor });
      const hasNextPage = rows.length > limit;
      const slice = rows.slice(0, limit);

      const edges = slice.map(post => ({ node: post, cursor: encodeCursor(post.id) }));
      return {
        edges,
        pageInfo: {
          hasNextPage,
          hasPreviousPage: !!cursor,
          startCursor: edges.at(0)?.cursor ?? null,
          endCursor: edges.at(-1)?.cursor ?? null,
        },
      };
    },
  },
};
```

## Errors

Two error surfaces:

| Type | Where | Use for |
|---|---|---|
| `errors[]` (GraphQLError) | Transport | Auth failures, malformed queries, server bugs |
| `userErrors[]` (payload field) | Mutation payload | Expected business errors (validation, conflict) |

```ts
import { GraphQLError } from 'graphql';

const resolvers = {
  Mutation: {
    async updatePost(_p, { id, input }, ctx: Context) {
      if (!ctx.viewer) {
        throw new GraphQLError('Authentication required', {
          extensions: { code: 'UNAUTHENTICATED', http: { status: 401 } },
        });
      }

      const post = await ctx.dataSources.posts.findById(id);
      if (!post) {
        return {
          post: null,
          userErrors: [{
            code: 'NOT_FOUND',
            field: ['id'],
            message: `No post with id ${id}`,
          }],
        };
      }
      if (post.authorId !== ctx.viewer.id) {
        throw new GraphQLError('Forbidden', {
          extensions: { code: 'FORBIDDEN', http: { status: 403 } },
        });
      }

      try {
        const updated = await ctx.dataSources.posts.update(id, input);
        return { post: updated, userErrors: [] };
      } catch (err: any) {
        if (err.code === 'CONFLICT') {
          return {
            post: null,
            userErrors: [{ code: 'CONFLICT', field: [], message: err.message }],
          };
        }
        throw new GraphQLError('Update failed', {
          extensions: { code: 'INTERNAL', cause: err.message },
        });
      }
    },
  },
};
```

## Interface and union resolvers

```ts
const resolvers = {
  SearchResult: {
    __resolveType(obj: Article | Video | Podcast) {
      if ('content' in obj) return 'Article';
      if ('duration' in obj && 'url' in obj) return 'Video';
      if ('audioUrl' in obj) return 'Podcast';
      throw new Error(`Unknown SearchResult type`);
    },
  },
  Query: {
    async searchContent(_p, { query }: { query: string }, ctx: Context) {
      const [a, v, p] = await Promise.all([
        ctx.dataSources.articles.search(query),
        ctx.dataSources.videos.search(query),
        ctx.dataSources.podcasts.search(query),
      ]);
      return [...a, ...v, ...p];
    },
  },
};
```

## Testing resolvers

```ts
describe('Post.author', () => {
  it('batches author lookups via DataLoader', async () => {
    const ctx = mockContext();
    const spy = jest.spyOn(ctx.dataSources.users, 'findByIds');
    const posts = [post1, post2, post3];

    await Promise.all(posts.map(p => resolvers.Post.author(p, {}, ctx)));

    expect(spy).toHaveBeenCalledTimes(1);
    expect(spy).toHaveBeenCalledWith([post1.authorId, post2.authorId, post3.authorId]);
  });
});
```

Prefer integration tests that exercise the full GraphQL pipeline — including
query parsing and auth — for critical paths.

## Rules

- Never create loaders at module scope.
- Always authorize in resolvers for sensitive fields or mutations.
- Use `userErrors` for expected domain failures; throw for transport errors.
- Preserve input order in DataLoader batch functions.
- Keep `context` creation < 50 ms; put expensive work in resolvers.
- Log with the `requestId` on every resolver error.
