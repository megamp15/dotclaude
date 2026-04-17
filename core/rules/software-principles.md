---
name: software-principles
description: Core software engineering principles — SOLID, DRY, YAGNI, KISS, and their limits
source: core
alwaysApply: true
---

# Software principles

Heuristics, not laws. Each has a failure mode when applied dogmatically.

## SOLID

**S — Single Responsibility.** A module/class has one reason to change. "Reason to change" is usually "stakeholder concern", not "feature".
- *Too far:* classes with one public method and a constructor. Responsibility is coarser than a method.

**O — Open/Closed.** Open for extension, closed for modification. Add new behavior by adding code, not by editing existing code.
- *Too far:* extension points for variations that never come. YAGNI wins here.

**L — Liskov Substitution.** Subtypes must be usable wherever the base type is, without surprising callers.
- *Litmus test:* if a subclass throws "not supported" on a base method, the hierarchy is wrong. Prefer composition.

**I — Interface Segregation.** Don't force clients to depend on methods they don't use. Many small interfaces > one fat one.
- *Too far:* single-method interfaces for everything. Group by cohesive role.

**D — Dependency Inversion.** High-level modules don't depend on low-level modules; both depend on abstractions.
- *Practical form:* inject dependencies; don't `new` them inside the code under test.
- *Too far:* abstracting every I/O call behind an interface for "testability" when a fake in the test would do.

## DRY — Don't Repeat Yourself

- **Real DRY is about knowledge, not text.** Two functions with similar shape but different *reasons* are not duplicates.
- Don't deduplicate until the third occurrence. Two is coincidence; three is a pattern.
- Wrong abstraction is more expensive than duplication. Sandi Metz: *"duplication is far cheaper than the wrong abstraction."*

## YAGNI — You Aren't Gonna Need It

- Don't add functionality, options, hooks, or abstraction points for imagined future needs.
- The cost of adding it later is almost always less than the cost of maintaining it forever.
- *Exception:* things that are very hard to add later (security, internationalization, observability, migrations).

## KISS — Keep It Simple, Stupid

- Simplest code that solves the problem wins.
- Simple ≠ easy. Simple is fewer moving parts, clearer names, obvious flow. Easy is whatever you already know.
- If a junior engineer can't follow the code in one read-through, it's probably too complex.

## Composition over inheritance

- Inheritance couples you to the parent's shape forever. Composition lets the pieces evolve.
- Deep inheritance (>2 levels) is almost always a mistake in application code.
- Use inheritance for true *is-a* relationships with substitutability; use composition for *has-a* / behavior mixing.

## Law of Demeter

Talk to your friends, not strangers. `user.address.city` across three layers couples them all.
- Expose the thing you need (`user.cityName()`) or pass it in.
- Getter chains through layers are a sign your boundaries are wrong.

## Fail fast, fail loud

- Invalid state should crash at the source, not silently propagate.
- Validate at boundaries, trust internally.
- Silent fallbacks ("if X is null, use default") hide bugs until they blow up somewhere distant.

## Principle of least astonishment

Code should behave the way a reasonable person reading it would expect.
- A function called `getUser` shouldn't create a user if missing.
- A method named `isValid` shouldn't have side effects.
- Equal-looking operations should be equally safe.

## Make the change easy, then make the easy change (Kent Beck)

Don't attempt a large refactor and a feature change at the same time.
1. Refactor so the change is easy (no behavior change, tests pass).
2. Make the change (small, focused, tested).
3. Separate commits for each.

## When principles conflict

They do, routinely. DRY pulls toward abstraction; YAGNI pulls against it. SRP pulls toward small classes; Demeter pulls toward fewer hops.

The real skill is **knowing when to apply which**, and recognizing that every principle has a failure mode when maximized. Good code lives in the tension between them, adjusted for the project's actual constraints (team size, change rate, reliability bar, domain complexity).
