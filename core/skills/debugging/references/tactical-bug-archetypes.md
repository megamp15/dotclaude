# Common bug archetypes

Recognize the shape; fix at the right level.

## Off-by-one & fence-post

**Shape:** loop runs one too many or one too few times. Index out of range, empty slice, missing last element.

**Root causes:** `<` vs `<=`, `len - 1` vs `len`, 0-indexed vs 1-indexed boundary.

**Fix level:** local. Usually one operator or one constant.

**Test:** boundary inputs — empty, single-element, exactly at the boundary, one over.

## Null / undefined propagation

**Shape:** crash deep in the stack when a value was missing upstream.

**Root causes:** optional field treated as required, `get()` returning `None` unchecked, un-awaited promise, uninitialized field.

**Fix level:** at the origin (make sure the value is never missing) OR at the boundary (validate + default). Never deep in the stack — that hides the cause.

**Test:** missing field, null input, uninitialized state.

## Race condition / TOCTOU

**Shape:** works under test, fails under load. Duplicate writes, lost updates, double spends.

**Root causes:** check-then-act without a lock, two requests racing the same row, async callback order.

**Fix level:** structural — transactional boundary, unique constraint, atomic operation (`SELECT FOR UPDATE`, `INSERT ... ON CONFLICT`, optimistic lock).

**Test:** concurrent repro. Fire N parallel requests, assert invariant.

## State pollution across tests / sessions

**Shape:** test passes alone, fails in suite. Or works first time, fails on replay.

**Root causes:** session-scoped fixture, module-level global, env var left set, temp dir reused, seeded random not reseeded.

**Fix level:** fixture or setup. Narrow fixture scope; reset state in teardown.

**Test:** run the same suite in reverse order, or repeat the failing test alone and in combo.

## Type coercion surprises

**Shape:** `"1" + 1 = "11"`, `0 == "0"` is true, `NaN !== NaN`, `float` comparison failing.

**Root causes:** implicit coercion, float equality, missing type guard at boundary.

**Fix level:** at the type boundary. Parse once, trust thereafter.

**Test:** the specific inputs that misbehaved, plus adjacent values.

## Missing index / N+1

**Shape:** fast in dev, slow in prod. Linear latency growth with data size.

**Root causes:** missing DB index, loop of queries, lazy-loaded relationship in serialization.

**Fix level:** data access layer. Add index, eager-load, batch.

**Test:** count queries in a perf test (`assert_num_queries(2)` in Django, similar elsewhere).

## Leaky resource

**Shape:** works for a while, degrades, crashes with "too many open files" or OOM.

**Root causes:** unclosed file/connection/handle, growing cache with no eviction, listener never unsubscribed.

**Fix level:** at resource lifecycle. Context manager, explicit close, bounded cache.

**Test:** loop the operation many times, assert resource count or memory stable.

## Silent swallowed error

**Shape:** the function returns "success" but nothing happened. Or the log is clean but the user reports failure.

**Root causes:** bare `except`, empty catch block, `.catch(() => {})`, error logged then discarded.

**Fix level:** at the catch. Narrow the exception type, or rethrow, or handle explicitly.

**Test:** inject the error condition; assert it's raised or reported.

## Wrong abstraction

**Shape:** bug keeps recurring in slightly different forms. Fixing one place breaks another. The "fix" keeps growing.

**Root causes:** the code is modeling the wrong thing, or modeling two things as one.

**Fix level:** structural. This is a redesign, not a patch. Stop and discuss before attempting.

**Signal:** you've fixed a similar bug in this area before.

## Environment drift

**Shape:** works on my machine.

**Root causes:** unpinned dep, OS-specific behavior, env var difference, different Python/Node version, clock skew, locale/encoding.

**Fix level:** pin, normalize, or explicitly handle the variation. Document the constraint.

**Test:** CI matrix, or a docker repro.
