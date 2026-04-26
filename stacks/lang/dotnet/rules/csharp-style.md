---
source: stacks/dotnet
name: csharp-style
description: C# code style and idioms — nullable, records, primary constructors, async/await discipline, LINQ, exceptions. Load when writing or reviewing C# code.
triggers: c#, csharp, nullable, record, primary constructor, async, await, task, linq, ef core, asp.net core, minimal api
globs: ["**/*.cs", "**/*.csproj", "**/Directory.Build.props", "**/Directory.Packages.props", "**/global.json"]
---

# C# style

Modern idioms. Targets .NET 8+ / C# 12+.

## Nullability

Every project: `<Nullable>enable</Nullable>`. No exceptions.

```csharp
// BAD — ignores the warning
public User GetUser(Guid id) => _db.Users.Find(id)!;

// BETTER — honest about nullability
public User? GetUser(Guid id) => _db.Users.Find(id);

// BEST — if the invariant is real, enforce it
public User GetUser(Guid id)
    => _db.Users.Find(id) ?? throw new UserNotFoundException(id);
```

Rules:

- `!` (null-forgiving) is a promise you can't prove. Every one needs justification.
- `?? throw` is fine when the invariant truly holds and failure is exceptional.
- Returning `T?` gives the caller the choice; often preferable to throwing.

## Records over classes for data

```csharp
// DTOs, value objects, messages, commands, events — all records
public record UserCreated(Guid UserId, string Email, DateTimeOffset CreatedAt);

public record Money(decimal Amount, string Currency)
{
    public Money Add(Money other)
    {
        if (Currency != other.Currency) throw new InvalidOperationException("Currency mismatch");
        return this with { Amount = Amount + other.Amount };
    }
}
```

- **Records are immutable** by default via init-only properties + value-based equality.
- **`with` expression** for derivation: `user with { Email = "new@x.com" }`.
- **`record struct`** for small, frequently-allocated value types.

Use classes when:

- The type has identity (entities with an `Id` you distinguish by).
- Mutation is part of the design (EF entities, stateful services).
- You need reference semantics.

## Primary constructors (C# 12+)

```csharp
public class OrderService(
    IOrderRepository orders,
    IPricingService pricing,
    ILogger<OrderService> logger)
{
    public async Task<Order> PlaceAsync(OrderRequest req, CancellationToken ct)
    {
        var price = await pricing.CalculateAsync(req.Items, ct);
        var order = new Order(req.CustomerId, req.Items, price);
        await orders.AddAsync(order, ct);
        logger.LogInformation("Placed order {OrderId}", order.Id);
        return order;
    }
}
```

- Parameters are in scope for all members.
- Cleaner than the old `_field = field ?? throw ...` boilerplate.
- Doesn't auto-create public properties — explicit if you need them.

## Async/await

### Rules

1. **Async all the way.** `sync → async` transitions cost a thread; deadlock-prone in sync contexts.
2. **Don't block on async code.** `.Result`, `.Wait()`, `.GetAwaiter().GetResult()` are forbidden outside a true sync boundary (Main in some contexts, certain test scenarios). Even then, prefer `Task.Run` + await patterns.
3. **Pass `CancellationToken` everywhere.** Every async method. Thread it through.
4. **Don't `async void`** except for event handlers.
5. **`ConfigureAwait(false)`** in libraries (code intended to be consumed elsewhere). Not in ASP.NET Core app code — no sync context, no benefit.
6. **`ValueTask`** only when profiling shows `Task` allocation is material.

### Patterns

```csharp
// Fire-and-forget — don't do this without logging.
// Unobserved exceptions crash the process in some runtimes.
_ = DoStuffAsync();   // NO

// Better: log errors explicitly.
_ = DoStuffAsync().ContinueWith(
    t => logger.LogError(t.Exception, "Background task failed"),
    TaskContinuationOptions.OnlyOnFaulted);

// Best: BackgroundService for long-running background work in ASP.NET Core.
```

```csharp
// Cancellation
public async Task<IReadOnlyList<User>> SearchAsync(string q, CancellationToken ct)
{
    await using var conn = await _factory.OpenAsync(ct);
    var cmd = new NpgsqlCommand("SELECT ... WHERE name ILIKE @q", conn);
    cmd.Parameters.AddWithValue("q", $"%{q}%");
    var users = new List<User>();
    await using var reader = await cmd.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
        users.Add(ReadUser(reader));
    return users;
}
```

## LINQ idioms

```csharp
// Readable and translatable to SQL (in EF Core)
var activeEmails = await _db.Users
    .Where(u => u.IsActive)
    .Select(u => u.Email)
    .ToListAsync(ct);

// Enumerate once
var items = await _db.Items.Where(...).ToListAsync(ct);
var total = items.Count;
var active = items.Count(i => i.IsActive);
// NOT: _db.Items.Where(...).Count() then .Count(i.IsActive) — two DB hits.

// Projection over full-entity materialization
var userDtos = await _db.Users
    .Where(u => u.IsActive)
    .Select(u => new UserDto(u.Id, u.Name, u.Email))
    .ToListAsync(ct);
```

Avoid:

- Mid-pipeline `.ToList()` — forces enumeration prematurely.
- Chaining LINQ over already-materialized data when DB would filter better.
- Method-per-operation (`.Where(...).Where(...).Where(...)`) when one predicate would do.

## Exception handling

```csharp
// GOOD — translate upstream error to domain error
try
{
    return await _httpClient.GetFromJsonAsync<Weather>(url, ct)
        ?? throw new WeatherUnavailableException();
}
catch (HttpRequestException ex)
{
    throw new WeatherUnavailableException("Upstream weather API failed", ex);
}

// BAD — catch + log + rethrow adds no value
try { return await DoAsync(); }
catch (Exception ex)
{
    _logger.LogError(ex, "Failed");
    throw;
}
```

If you're not going to translate, enrich, or recover, don't catch. Let it bubble.

For top-level ASP.NET handling, use `UseExceptionHandler` with `ProblemDetails`, or `IExceptionHandler` (middleware-composed).

## Collections + data structures

- **Return `IReadOnlyList<T>` or `IReadOnlyCollection<T>`** from methods whose callers don't need to mutate. Use `List<T>` internally.
- **`IEnumerable<T>` in parameters** only when lazy semantics are intentional. Materialize to `.ToList()` at the boundary if you're going to enumerate multiple times.
- **`ImmutableArray<T>` / `ImmutableList<T>`** for truly immutable shared state.
- **`Frozen*<T>`** (`FrozenDictionary`, `FrozenSet`) for read-heavy, write-once lookups — faster than regular after freezing.

## File-scoped namespaces

```csharp
namespace MyApp.Application.Users;

public class UserService { ... }
```

One level of indentation saved; cleaner. Don't keep the old block-scoped namespace.

## `using` directives

- `global using` declarations (in a `GlobalUsings.cs`) for commonly-used namespaces across the project. Pairs with `<ImplicitUsings>enable</ImplicitUsings>` for framework namespaces.
- Sorted: System first, then others. Editor handles this; `dotnet format` enforces.

## Patterns vs. abstractions

- **Pattern matching** is your friend:
  ```csharp
  var summary = user switch
  {
      { IsAdmin: true } => "admin",
      { IsActive: false } => "inactive",
      _ => "user",
  };
  ```
- **Switch expressions** over if-elif-else chains for data → value transformations.
- **`is not null`** over `!= null` — clearer intent.

## Testing idioms

```csharp
public class UserServiceTests
{
    [Fact]
    public async Task GetUser_WhenFound_ReturnsUser()
    {
        // Arrange
        var repo = Substitute.For<IUserRepository>();
        repo.GetByIdAsync(Arg.Any<Guid>()).Returns(new User(Guid.NewGuid(), "a@b.com"));
        var svc = new UserService(repo, NullLogger<UserService>.Instance);

        // Act
        var result = await svc.GetAsync(Guid.NewGuid(), CancellationToken.None);

        // Assert
        result.Should().NotBeNull();
        result!.Email.Should().Be("a@b.com");
    }
}
```

- Arrange/Act/Assert structure, blank lines between.
- Descriptive test names: `Method_Condition_ExpectedResult`.
- One logical assertion per test (multi-line FluentAssertions OK if asserting one object's shape).

## Review checklist

- [ ] `Nullable enable`; no unnecessary `!` (null-forgiving).
- [ ] Async methods accept `CancellationToken` and honor it.
- [ ] No `.Result` / `.Wait()` / `async void` (outside event handlers).
- [ ] Exceptions only caught to translate/enrich/recover.
- [ ] Records used for DTOs/value objects; classes for entities/services.
- [ ] `ILogger<T>` with structured templates, not string concatenation.
- [ ] DbContext lifetime is Scoped; queries use `AsNoTracking()` when read-only.
- [ ] Primary constructors used for DI-heavy classes (C# 12+).
- [ ] `TypedResults` in Minimal APIs (for OpenAPI).
- [ ] Secrets from configuration / Key Vault / Secrets Manager, not hard-coded.
