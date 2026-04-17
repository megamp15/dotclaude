# Universal review checklist

Run through this mentally regardless of language. Most findings come from
the same questions.

## The change itself

- Does the change do what the title/description claims?
- Is the scope tight, or are there drive-by edits?
- Are unrelated refactors mixed with behavior changes? (They shouldn't be.)

## Correctness

- Any obvious bugs — off-by-one, null deref, wrong operator, inverted condition?
- What happens on empty input, large input, malformed input, duplicate input?
- Does the error path handle the errors that actually happen, or only the ones the author imagined?
- Are there concurrency assumptions (lock held, single writer, ordering) that the code doesn't enforce?

## Tests

- Is there a test that fails without the change and passes with it?
- Are new branches covered?
- Does any test just check `is not None` / `toBeDefined`?
- Any test that would pass if the implementation were deleted?

## API & contract

- Public signatures changed? Who calls them?
- Breaking change to config, DB schema, serialized format? Migration story?
- Deprecation path for removed/renamed things?

## Performance

- N+1 queries? Unbounded loops? Big payloads?
- Blocking I/O where async was expected?
- Any new caching — is it bounded, invalidated correctly?

## Security

- User input: validated at every trust boundary?
- Secrets in the diff, in logs, in error messages?
- Auth/authz checks on new endpoints?
- Unsafe deserialization, eval, dynamic import?

## Observability

- New failure modes — is there a log / metric / trace to find them?
- Error messages useful enough to debug at 3am?

## Readability

- Would a new teammate understand what this does and why?
- Any clever code that should be obvious instead?
- Comments that explain *why*, not *what*?

## Docs

- New public API, new config, new environment variable — is it documented?
- Existing docs still accurate after the change?

## Rollback

- If this is wrong in production, how do we back it out? Fast or slow?
- Is there any destructive side effect (migration run, data rewritten) that makes rollback hard?
