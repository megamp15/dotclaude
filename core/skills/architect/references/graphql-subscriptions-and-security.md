---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/graphql-architect/references
ported-at: 2026-04-17
adapted: true
---

# Subscriptions and security hardening

## Subscriptions

### When to use

Real-time updates have real cost (persistent connections, pub/sub infra).
Use only when:

- Polling doesn't meet the UX need (sub-second updates for many clients).
- The event is genuinely pushed by the server (status change, incoming
  message), not "the UI wants to know".

Don't use for: dashboards that refresh every 30 s (polling is fine), or
generic data freshness (use query invalidation).

### Schema

```graphql
type Subscription {
  messageAdded(channelId: ID!): Message!
  orderStatusChanged(orderId: ID!): Order!
  notificationReceived: Notification!
}
```

### Transport

Use `graphql-ws` over WebSockets — not the deprecated
`subscriptions-transport-ws`.

```ts
import { useServer } from 'graphql-ws/lib/use/ws';
import { WebSocketServer } from 'ws';

const wsServer = new WebSocketServer({ server: httpServer, path: '/graphql' });
useServer(
  {
    schema,
    context: async (ctx) => {
      const token = ctx.connectionParams?.authorization;
      const viewer = await verifyToken(token);
      if (!viewer) throw new Error('UNAUTHENTICATED');
      return { viewer };
    },
    onSubscribe: (ctx, msg) => {
      // Per-subscription auth check
    },
  },
  wsServer,
);
```

### Resolver

```ts
import { withFilter } from 'graphql-subscriptions';

const resolvers = {
  Subscription: {
    messageAdded: {
      subscribe: withFilter(
        (_p, _a, ctx) => ctx.pubsub.asyncIterator('MESSAGE_ADDED'),
        async (payload, { channelId }, ctx) => {
          if (payload.message.channelId !== channelId) return false;
          return await ctx.authorizer.canReadChannel(ctx.viewer, channelId);
        },
      ),
      resolve: (payload) => payload.message,
    },
  },
};
```

**Critical:** re-check authorization on every emission — a user's permissions
can change during a long-lived subscription.

### Scaling pub/sub

- In-process `PubSub` is fine for a single instance and local dev only.
- For production, use Redis pub/sub, Kafka, NATS, or Google Pub/Sub.
- Plan for connection limits — most servers cap at 10k–100k concurrent
  connections per instance.

## Security hardening

### Depth, breadth, cost

Without limits, a single malicious query can DoS the server.

```ts
import depthLimit from 'graphql-depth-limit';
import costAnalysis from 'graphql-cost-analysis';

const server = new ApolloServer({
  schema,
  validationRules: [
    depthLimit(10),
    costAnalysis({
      maximumCost: 1000,
      defaultCost: 1,
      variables: {},
      createError: (max, actual) =>
        new GraphQLError(`Query too expensive: ${actual} > ${max}`),
    }),
  ],
});
```

Assign costs per field based on expected work:
- Simple field resolvers: 1
- Foreign-key lookups: 5
- List fields: `multiplier * limit`
- Full-text search: 50+

### Query timeouts

```ts
new ApolloServer({
  schema,
  plugins: [
    {
      requestDidStart() {
        return {
          async willSendResponse(ctx) {
            if (ctx.metrics.responseCacheHit) return;
          },
        };
      },
    },
  ],
});

// At HTTP layer
app.use('/graphql', (req, res, next) => {
  req.setTimeout(30_000);
  next();
});
```

### Persisted queries (for known clients)

Only accept queries by SHA256 identifier for your own frontends:

```json
{
  "extensions": {
    "persistedQuery": {
      "version": 1,
      "sha256Hash": "abc123..."
    }
  },
  "variables": { "id": "ord_01HBX" }
}
```

Unknown hashes → rejected. Public exploratory queries → only on staging or
behind auth.

### Introspection

- Enabled in dev and staging.
- **Disabled or restricted to authenticated admins** in production for apps
  with sensitive schemas. An exposed introspection endpoint is a full map of
  your attack surface.

```ts
new ApolloServer({
  schema,
  introspection: process.env.NODE_ENV !== 'production',
});
```

### Error responses

Never leak internals:

```ts
import { unwrapResolverError } from '@apollo/server/errors';

new ApolloServer({
  schema,
  formatError: (formatted, err) => {
    const original = unwrapResolverError(err);
    if (formatted.extensions?.code === 'INTERNAL_SERVER_ERROR') {
      logger.error({ err: original }, 'graphql internal error');
      return {
        message: 'Internal server error',
        extensions: {
          code: 'INTERNAL',
          requestId: (err.extensions as any)?.requestId,
        },
      };
    }
    return formatted;
  },
});
```

Never return stack traces, SQL fragments, or PII in `message`.

### CORS and CSRF

- Strict CORS allow-list; no `*` in production.
- CSRF protection: Apollo Server has built-in CSRF prevention — enable it.
  Reject requests missing a preflight header for non-GET operations.

### Authentication

- Bearer tokens via `Authorization` header.
- For browser subscriptions, use the WS `connectionParams` — don't put
  tokens in the URL.
- Validate tokens in context; reject unauthenticated requests early.

### Rate limiting

Per user and per operation. Heavy mutations or expensive queries get tighter
budgets.

```ts
// Conceptual — integrate with redis-based limiter
const limits = {
  createOrder: { perUser: '10/min', global: '1000/min' },
  searchProducts: { perUser: '60/min' },
};
```

### Field-level auth

Don't trust the query structure. Authorize in resolvers for sensitive fields:

```ts
const resolvers = {
  User: {
    email: (u, _a, ctx) =>
      ctx.viewer?.id === u.id || ctx.viewer?.isAdmin ? u.email : null,
    stripeCustomerId: (u, _a, ctx) =>
      ctx.viewer?.isAdmin ? u.stripeCustomerId : null,
  },
};
```

## Hardening checklist

- [ ] Depth limit enforced
- [ ] Cost analysis enforced
- [ ] Per-operation rate limits
- [ ] Query timeouts
- [ ] Persisted queries for first-party clients
- [ ] Introspection disabled / gated in prod
- [ ] Error messages sanitized; internals logged, not returned
- [ ] Auth checked on every sensitive field, not just at the gateway
- [ ] Subscriptions re-authorize on every emission
- [ ] CSRF prevention enabled
- [ ] Strict CORS allow-list
- [ ] CI fails on schema changes that add sensitive fields without auth directives
