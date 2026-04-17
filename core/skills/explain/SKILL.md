---
name: explain
description: Explain a file, function, or concept from the codebase. Focuses on the why, the mental model, and the landmines — not the obvious.
source: core
triggers: /explain, explain this, walk me through, what does this do, how does X work
---

# explain

Produce an explanation a new teammate could actually use. Lead with the
mental model. Skip the obvious.

## Structure (in order)

### 1. One-sentence summary

What this is, in 20 words. If the name already conveys it, lead with what's surprising instead.

### 2. Mental model

An analogy or simpler system this is like. "It's a queue with priorities." "It's a cache with a TTL but no eviction." Pick something the reader already understands.

### 3. Shape / diagram

A small ASCII diagram of the data flow or call structure. Keep it under 10 lines. Show:

- Inputs (where calls come from)
- Key internal pieces
- Outputs (where values go)

Skip if it's trivial (a single pure function).

### 4. Key non-obvious details

The things the code does that a casual read would miss:

- Invariants maintained
- Ordering that matters
- State that persists across calls
- Side effects
- Performance characteristics (this is O(n²), this is amortized O(1))

### 5. Landmines

What breaks if modified carelessly:

- "Don't change the order of these two lines — A must be true before B."
- "This function is called from a hot path; adding I/O here will hurt."
- "This relies on `input.items` being sorted by the caller."
- "This used to do X; it was changed to Y because Z. Don't revert without understanding."

### 6. Modification guide

The two or three most likely changes and where they go:

- "Adding a new X: add a case to the `handlers` dict at line Y."
- "Changing the retry count: config in `settings.py`, not inline."
- "Adding a new output format: implement the `Writer` protocol in `formats/`."

### 7. See also

Related code worth reading next — callers, tests, docs, linked issues.

## What NOT to include

- Paraphrased code: "This loops through each user and..." The reader can see that.
- Boilerplate: imports, simple getters, standard library behavior.
- Every branch. Cover the *important* branches; skip the obvious ones.
- Docstring contents verbatim — link to them.

## How to behave

- Keep it short. A 40-line explanation beats a 400-line one.
- Use specific line numbers. `handle_request()` is vague; `handle_request() at server.py:L142` is useful.
- Be honest about what you don't know. "I'm not sure why this branch is here — the commit message just says 'edge case fix'. May be worth asking [author]."
- If the code is bad, say so — tactfully. "This is a legitimate smell; a refactor is worth considering" is fine.
- If the concept has a standard name (Observer pattern, token bucket, linked list, etc.), name it so the reader can learn more elsewhere.
