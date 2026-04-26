---
description: Append a new entry to .claude/learnings.md — the project's append-only log of non-obvious discoveries (gotchas, hidden couplings, intentional weirdness). Zero-dep cross-session memory.
---

Append a new entry to `.claude/learnings.md` per the discipline in
`.claude/skills/learnings-log/SKILL.md`.

## How to use

The user can invoke this with or without an argument:

- **`/dotclaude-learn <one-line summary>`** — capture mode. Use the
  argument as the topic phrase. Draft a 1-3 line body from the
  current conversation context (what was just discussed/discovered).
  Add `tags:` if relevant areas are obvious.

- **`/dotclaude-learn`** (no argument) — interview mode. Ask the user
  one question: "What did you just discover that the next agent
  should know?" Then turn their answer into an entry following the
  template.

## Steps

1. **Locate the file.** `.claude/learnings.md` — if it doesn't exist,
   create it with the seed header from
   `.claude/skills/learnings-log/references/learnings-template.md`.

2. **Compose the entry** in the canonical format:

   ```markdown
   ## YYYY-MM-DD — short topic phrase

   Body (1-3 lines). Name actual files and symbols when applicable.

   tags: area, area
   ```

   Use today's date (ISO format). Body should name file paths,
   function/symbol names, PR numbers, or commands when relevant —
   vague entries are worse than no entry.

3. **Insert at the top.** Newest entries go on top of the file (right
   after the header / HTML comment block, before any existing entries).
   This is opposite of a chronological journal — it's how the conductor
   brief surfaces the most recent N entries cheaply.

4. **Show the user the entry before writing.** One short confirmation:
   "About to append this to learnings.md: [entry]. OK?" Wait for
   confirmation. Single-entry appends are low-friction but not silent.

5. **After appending,** print: "Logged. Next conductor brief will
   surface this in the top 3."

## Anti-patterns

- **Don't log normal progress.** "Implemented function `foo`" is a
  commit message. The learnings log is for discoveries, not status.
- **Don't log secrets.** Redact tokens, keys, internal URLs, customer
  data — even in "I tried this" notes.
- **Don't log noise.** "Fixed a typo." Skip.
- **Don't log things grep would find.** If the next agent could
  discover it by reading the code, it's not a learning.
- **Don't write more than 3 body lines.** If you need more, you're
  trying to log two thoughts. Split into two entries.

If unsure whether the thing is worth logging, default to skipping.
The bar is intentionally high; the log stays high-signal.

$ARGUMENTS
