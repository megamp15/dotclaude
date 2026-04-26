---
source: stacks/dotnet
---

# Stack: .NET

Conventions for .NET (C#) projects. Layers on `core/`. Version target:
**.NET 8 LTS or .NET 9** (as of 2026). Patterns below assume modern
.NET — nullable reference types, minimal APIs, DI-by-default, top-level
statements, records.

If the project is on .NET Framework (4.x, the old Windows-only one)
these rules only partially apply. Prefer migration to .NET 8+ when
feasible.

## Project layout — one pattern that scales

```
MyApp/
├── global.json                          # pins SDK version
├── Directory.Packages.props             # centralized package versions
├── Directory.Build.props                # shared MSBuild settings
├── .editorconfig                        # formatting + style rules
├── MyApp.sln
├── src/
│   ├── MyApp.Api/                       # ASP.NET Core entry
│   │   ├── MyApp.Api.csproj
│   │   ├── Program.cs
│   │   └── Endpoints/
│   ├── MyApp.Application/               # use-cases, orchestration
│   ├── MyApp.Domain/                    # entities, domain logic
│   └── MyApp.Infrastructure/            # EF Core, integrations
└── tests/
    ├── MyApp.Api.Tests/
    ├── MyApp.Application.Tests/
    └── MyApp.Domain.Tests/
```

A layered structure (API → Application → Domain, with Infrastructure
referenced as needed) keeps the domain core free of framework concerns.
Works for microservices and monoliths alike; for tiny apps, collapse
layers — don't forge ceremony.

## Solution-level hygiene

### `global.json` — pin the SDK

```json
{
  "sdk": {
    "version": "8.0.100",
    "rollForward": "latestFeature"
  }
}
```

Commit it. Team + CI use the same SDK.

### `Directory.Packages.props` — central package versions

Enables **CPM (Central Package Management)**:

```xml
<Project>
  <PropertyGroup>
    <ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>
  </PropertyGroup>
  <ItemGroup>
    <PackageVersion Include="Microsoft.EntityFrameworkCore" Version="8.0.10" />
    <PackageVersion Include="Serilog.AspNetCore" Version="8.0.3" />
  </ItemGroup>
</Project>
```

Individual `.csproj` files use `<PackageReference Include="..." />` without a version. Upgrade once; apply everywhere.

### `Directory.Build.props` — shared settings

```xml
<Project>
  <PropertyGroup>
    <LangVersion>latest</LangVersion>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <AnalysisLevel>latest-all</AnalysisLevel>
    <EnableNETAnalyzers>true</EnableNETAnalyzers>
  </PropertyGroup>
</Project>
```

- **`Nullable enable`** is non-negotiable. The compiler knowing about nullability is the single biggest win of modern C#.
- **`TreatWarningsAsErrors true`** forces everyone to fix warnings instead of accumulating them.
- **`AnalysisLevel latest-all`** turns on all analyzers — some are noisy; tune in `.editorconfig`.

### `.editorconfig`

Format + style rules. Run `dotnet format` in CI.

## Language conventions (C#)

### Types

- **Records over classes for DTOs and value objects.** `public record User(Guid Id, string Email);` — concise, immutable, value-based equality.
- **Primary constructors** (C# 12+) for DI-heavy classes:
  ```csharp
  public class UserService(IUserRepository repo, ILogger<UserService> logger)
  {
      public async Task<User> Get(Guid id) => await repo.GetByIdAsync(id);
  }
  ```
- **`sealed` classes** by default unless designed for inheritance.
- **`readonly`** on fields that shouldn't change post-construction.
- **`init`** for properties that set at construction then stay fixed.

### Null handling

- Leverage nullable reference types. `string? name` means "could be null"; `string name` means "definitely not null."
- **Avoid `!`** (null-forgiving) — every `!` is a claim you can't prove. Use it sparingly; add a comment when you do.
- **Avoid `x ?? throw ...`** when the caller could just take a `T?` and handle. Only throw when the invariant is genuinely broken.

### `async` discipline

- **Async all the way down.** A sync method calling an async one via `.Result` / `.GetAwaiter().GetResult()` is a deadlock waiting to happen.
- **`ConfigureAwait(false)`** in libraries — not needed in ASP.NET Core app code (no sync context in the server pipeline).
- **`CancellationToken`** threaded through every async method. ASP.NET Core gives you `HttpContext.RequestAborted`; pass it.
- **`ValueTask`** only when profiling shows `Task` allocation is a bottleneck. Default to `Task` / `Task<T>`.
- **`await foreach`** for `IAsyncEnumerable<T>` — streaming results without buffering.

### LINQ

- **Readable over clever.** Method syntax (`.Where().Select()`) for most code; query syntax for complex joins.
- **`.ToList()` / `.ToArray()` only when you need materialization.** Chaining LINQ over `IEnumerable<T>` is lazy; `.ToList()` forces evaluation — don't do it mid-pipeline.
- **Enumerate once.** `var items = query.ToList()` if you're going to enumerate it twice; otherwise two DB queries.

### Exceptions

- **Don't throw `Exception`**, throw specific types.
- **Don't catch `Exception`** except at a top-level boundary (ASP.NET middleware, background service) where you log and re-raise or respond.
- **`try`/`catch` only to translate or enrich.** Bare catch-rethrow is noise.

## ASP.NET Core (minimal APIs)

### Program.cs — the modern shape

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddOpenApi();              // .NET 9+
builder.Services.AddDbContext<AppDb>(o => o.UseNpgsql(builder.Configuration.GetConnectionString("Db")));
builder.Services.AddScoped<IUserService, UserService>();
builder.Services.AddProblemDetails();       // RFC 7807 errors

var app = builder.Build();

app.UseExceptionHandler();                  // global exception → ProblemDetails
app.UseHttpsRedirection();
app.UseAuthentication();
app.UseAuthorization();

app.MapUsers();   // extension method that groups endpoints
app.MapHealthChecks("/health");

app.Run();
```

### Endpoint grouping

```csharp
public static class UserEndpoints
{
    public static void MapUsers(this WebApplication app)
    {
        var group = app.MapGroup("/users").RequireAuthorization().WithTags("Users");
        group.MapGet("/{id:guid}", GetUser);
        group.MapPost("/", CreateUser);
    }

    private static async Task<Results<Ok<User>, NotFound>> GetUser(
        Guid id, IUserService users, CancellationToken ct)
    {
        var user = await users.GetAsync(id, ct);
        return user is null ? TypedResults.NotFound() : TypedResults.Ok(user);
    }
}
```

- **`TypedResults`** over `Results` — it's strongly typed; OpenAPI sees the response types.
- **Route-level policies** (`.RequireAuthorization()`) apply to the group.
- **CancellationToken** on every endpoint; ASP.NET injects `RequestAborted`.

### MVC vs Minimal APIs

- **Minimal APIs** for most HTTP surfaces — less ceremony, good perf, great OpenAPI.
- **MVC Controllers** when you need filters / ModelBinder / heavy conventions. Legacy code already on controllers: fine to stay.
- **Don't mix them for the same feature** — pick one per service.

### ProblemDetails for errors

Return RFC 7807 `ProblemDetails` responses. `AddProblemDetails()` + `UseExceptionHandler()` handles uncaught exceptions. For expected errors, return `TypedResults.Problem(...)`.

## Dependency injection

- **Built-in DI container** is fine for 95% of apps. Reach for Autofac / Simple Injector only when the feature set earns it.
- **Lifetimes**:
  - `Singleton` — stateless services, caches, config.
  - `Scoped` — per-request (DbContext, request-scoped user info). Default for most services.
  - `Transient` — cheap, stateless, new per resolution. Don't use for anything non-trivial.
- **Don't inject a `Scoped` into a `Singleton`.** Capture leaks. The compiler won't catch it; your tests should.
- **Constructor injection** over service location (`IServiceProvider.GetService`). Explicit deps, testable.

## EF Core

- **`DbContext` is Scoped**, not Singleton. Each request / unit-of-work gets one.
- **No `DbContext.Database.EnsureCreated()` in production** — migrations.
- **Migrations**: `dotnet ef migrations add X` in dev; migration scripts applied in CI / at startup carefully.
- **Avoid `.Include()` chains** — easily N+1. Use projection (`.Select(u => new UserDto {...})`) when possible.
- **`AsNoTracking()` for read-only queries** — cuts memory + speeds up.
- **`ToListAsync()` / `FirstOrDefaultAsync()`** — always async.
- **Watch for implicit `Func<>` materialization.** `.Where(x => x.Status == MyEnum.Active)` works; `.Where(x => SomeMethod(x))` may materialize and run client-side.

## Configuration

- **`IConfiguration`** layered: `appsettings.json` → `appsettings.{Environment}.json` → env vars → command line.
- **Options pattern** (`IOptions<T>` / `IOptionsSnapshot<T>`) — typed config sections:
  ```csharp
  public class SmtpOptions { public string Host { get; set; } = ""; public int Port { get; set; } = 587; }

  builder.Services.Configure<SmtpOptions>(builder.Configuration.GetSection("Smtp"));
  ```
- **Secrets**: `dotnet user-secrets` in dev; KeyVault / Secrets Manager / SOPS in prod. Never in `appsettings.json`.

## Logging

- **Structured logging** via `ILogger<T>`. Use message templates, not string concatenation:
  ```csharp
  logger.LogInformation("User {UserId} logged in from {Ip}", userId, ip);  // GOOD
  logger.LogInformation($"User {userId} logged in from {ip}");              // BAD
  ```
- **Serilog** is the common choice for richer sinks + enrichers. Configure it at program start.
- **`LogLevel`** per category in `appsettings.json`. Default to `Information`; reduce noisy libraries to `Warning`.

## Testing

- **xUnit** is the default. NUnit and MSTest work; don't switch without reason.
- **FluentAssertions** for readable asserts: `result.Should().Be(expected)`.
- **Testcontainers** for integration tests against real Postgres / Redis / etc. Better than in-memory fakes.
- **WebApplicationFactory<TEntryPoint>** for ASP.NET integration tests — spins up an in-process server.
- **Moq / NSubstitute** for mocking. One per project; don't mix.
- **Arrange / Act / Assert** structure; one logical assertion per test.

## Performance

- **Strings**: `StringBuilder` for multi-append in hot loops; interpolation is fine for one-offs.
- **Spans / Memory<T>**: reach for them when perf-profiling demands; not every hot path needs them.
- **Pooling**: `ArrayPool<T>.Shared.Rent(n)` for temporary buffers in very hot code.
- **`async` state machine allocations**: `ValueTask` only when this shows up in profiling.
- **Profile before optimizing.** `dotnet-counters`, `dotnet-trace`, PerfView.

## Do not

- Do not use `.Result` or `.Wait()` on Tasks — deadlocks in sync contexts.
- Do not swallow exceptions (`catch { }`) — you'll regret it.
- Do not put secrets in `appsettings.json`.
- Do not disable `TreatWarningsAsErrors` — fix warnings.
- Do not use `dynamic` except for true interop with dynamic languages.
- Do not create a `HttpClient` per request — use `IHttpClientFactory`.
- Do not let EF Core materialize unnecessary data (full-entity queries when a DTO projection would do).
- Do not mix Minimal APIs and MVC controllers for the same feature area without a reason.
- Do not ignore `CancellationToken` parameters — they exist to cancel; honor them.
