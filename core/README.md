# core

Universal layer. Everything here applies to **every** project regardless of
language, framework, or domain. Stack-specific content lives in `stacks/`;
project-specific content comes from the init interview.

## What's in here

```
core/
├── CLAUDE.base.md         # universal CLAUDE.md content — tone, principles, guardrails
├── settings.partial.json  # universal permissions + hooks registration
├── rules/                 # universal coding + process rules
├── skills/                # universal workflows (pr-review, ship, testing, debugging, etc.)
├── agents/                # universal specialist reviewers
├── hooks/                 # universal guardrail scripts (dangerous-commands, secrets, etc.)
└── mcp/                   # always-on + opt-in MCP servers
```

## Inclusion rules for `core/`

Every file here must pass all three:

1. **Language-agnostic.** If it mentions a specific language or framework,
   it belongs in `stacks/<category>/<name>/`, not here.
2. **Domain-agnostic.** No billing / auth / game / ML / embedded specifics.
   Those belong in project-specific rules.
3. **Free.** No paid MCP servers, no paid-tier-only workflows.

When in doubt, ask: *would this still be useful in a COBOL project maintained
by a solo dev?* If yes, `core/`. If no, `stacks/` or project-level.

## What's intentionally NOT here

- Language style rules (`ruff`, `prettier`, `rustfmt`) → `stacks/`
- Framework patterns (`next`, `django`, `rails`) → `stacks/`
- Business rules (billing, auth flows, domain logic) → project
- Personal preferences (editor, OS notifications) → `settings.local.json`

## Extending core

Adding to `core/` is a high bar. Before adding:

- Check the three inclusion rules above.
- Confirm the file name is unique across all stacks (the merge rules
  deep-merge by filename — collisions let stacks override core).
- Add a `source: core` frontmatter tag (for markdown) or header comment
  (for scripts/JSON) so the init skill can tag copies correctly.
