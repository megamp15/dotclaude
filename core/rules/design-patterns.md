---
name: design-patterns
description: Common design patterns — when to use, when NOT to use, and simpler alternatives
source: core
alwaysApply: false
triggers: design pattern, refactor, architecture, factory, strategy, observer, singleton, repository, adapter, decorator
---

# Design patterns

Patterns are vocabulary, not mandates. Reach for a pattern when it
removes real pain — not to look clever.

## Decision rules

- **Default to the simplest thing.** Functions > classes. Composition > inheritance. Local variables > global state.
- **Introduce a pattern when the shape of the problem demands it**, not when the tutorial you read last week mentioned it.
- **Name the pattern in the code** if it helps future readers. `OrderFactory`, `PaymentStrategy`, `UserRepository`.

## Creational

| Pattern | Use when | Don't use when | Simpler alternative |
|---|---|---|---|
| **Factory** | Construction is non-trivial, varies by input, or creates different subtypes | A constructor would do | Plain function, static method |
| **Builder** | Many optional params, immutable result, validation needed | <5 params | Named args / dataclass / object literal |
| **Singleton** | One instance must exist globally AND construction is expensive | You just want a shared config | Module-level variable / DI container |
| **Prototype** | Cloning is cheaper than reconstructing | Objects are immutable or cheap to build | Copy constructor, `.copy()` |

**Singleton warning:** in most languages, a regular module with a single instance variable is a singleton without the ceremony. "Real" singletons with lazy init + locking are a code smell unless you've profiled it.

## Structural

| Pattern | Use when | Don't use when |
|---|---|---|
| **Adapter** | Wrapping a third-party API to match your interface | You own both sides — just change one |
| **Facade** | Simplifying a complex subsystem for common cases | There's only one complex call |
| **Decorator** | Adding orthogonal behavior (logging, caching, auth) without modifying the target | One-off behavior add |
| **Proxy** | Controlling access (lazy load, cache, access control, remote) | You just want dependency injection |
| **Composite** | Tree of uniform things (UI components, org chart) | Flat list |

## Behavioral

| Pattern | Use when | Don't use when |
|---|---|---|
| **Strategy** | Swappable algorithms with the same interface | Only 2 cases and they'll never grow |
| **Observer / Pub-Sub** | One event, many reactions, reactions don't know each other | Direct call graph is clearer |
| **Command** | Operations need undo, queueing, or logging | Just want a callable |
| **Template method** | Most of an algorithm is shared, a few hooks vary | Strategy pattern fits better and is more composable |
| **Iterator** | Custom traversal over a structure | The language gives you one (most do) |
| **State** | Object's behavior changes with internal state, and there are >3 states | `if self.state == X` is fine for small cases |
| **Chain of Responsibility** | Request flows through handlers, any of which can short-circuit | Linear function calls are clearer |

## Domain-oriented

| Pattern | Use when | Notes |
|---|---|---|
| **Repository** | Abstracting data access so business code doesn't know about the DB | Don't make the repo a leaky ORM wrapper |
| **Unit of Work** | Coordinating multiple repo mutations in one transaction | Usually your ORM already has this |
| **Service layer** | Business logic doesn't fit in an entity | Keep thin; don't make services a dumping ground |
| **Value Object** | Small immutable thing with identity-by-value (`Money`, `EmailAddress`) | Prefer over primitives for domain concepts |
| **Entity** | Thing with identity that persists through state changes | Don't model CRUD tables as entities — they're DTOs |
| **Aggregate** | Cluster of entities with a root that enforces invariants | Keep small; large aggregates are a performance bomb |

## Anti-patterns to avoid

- **God object** — one class doing many unrelated things. Split by responsibility.
- **Anemic domain model** — entities with only data, all logic in services. Put behavior where the data is.
- **Premature abstraction** — `IFooFactoryProvider<T>` before you have two implementations. Wait for the second real case.
- **Speculative generality** — options, hooks, and extension points "just in case". YAGNI.
- **Pattern fatigue** — naming every function after a pattern (`OrderFacadeStrategy`). Readers should understand intent, not decode your pattern catalogue.

## When refactoring toward a pattern

1. Verify the pain is real (duplicate code, rigid switch statements, growing conditional trees).
2. Write a test that exercises the current behavior.
3. Apply the pattern in the smallest viable scope.
4. Check: does the new code read better? If not, back it out.

The right question is rarely "which pattern?" — it's "what's making this code hard to change?"
