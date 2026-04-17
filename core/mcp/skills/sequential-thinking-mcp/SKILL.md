---
name: sequential-thinking-mcp
description: Structured multi-step reasoning via the Sequential Thinking MCP. Use for genuinely multi-step problems where the reasoning needs to be visible and revisable, not for routine questions.
source: core/mcp
triggers: think step by step, plan this out, break this down, work through this carefully, complex reasoning
---

# sequential-thinking-mcp

A structured way to externalize reasoning for problems that genuinely
benefit from step-by-step thinking — planning, decomposition, problems
where intermediate steps can be wrong and need revising.

## When to use

- **Multi-step planning** — "design a migration path from X to Y".
- **Root-cause analysis** where the path from symptom to cause is non-obvious.
- **Architectural decisions** with interacting constraints.
- **Algorithm design** — break down, test cases, corner cases.
- **Debugging problems** where you keep getting stuck and need to back up.

The key signal: the problem has **branches you might need to back out of**.

## When NOT to use

- **Factual questions** with a direct answer.
- **Simple tasks** — editing a file, running a command, reading a log.
- **Routine code changes** — write the code; don't narrate the planning.
- **Anything under ~3 real reasoning steps.** If it fits in your head, just answer.

Using sequential-thinking for every question is noise, eats tokens, and
makes the agent appear indecisive. Reserve it for real uses.

## How it works

The MCP provides a `sequentialthinking` tool that you call iteratively:

- Each call adds one thought with a number and a total-so-far estimate.
- Thoughts can be **revisions** of earlier thoughts — signals that the previous step was wrong.
- Thoughts can **branch** — explore two directions, return to a prior point.
- The tool tracks the chain; you can refer back to previous steps.

Typical structure:

1. **Frame** — restate the problem in precise terms.
2. **Enumerate** — list sub-questions, constraints, unknowns.
3. **Explore** — work through each; flag dead ends.
4. **Synthesize** — combine the findings.
5. **Conclude** — one clear answer or recommendation.

## Patterns

### Planning a migration

```
1. Frame: we need to go from Postgres 13 to 16 with zero downtime
2. List constraints: < 5s window, existing replication, X GB of data
3. Enumerate approaches: logical replication, pg_dump + restore, blue/green
4. Rule out pg_dump (too slow at X GB)
5. Compare logical replication vs blue/green on operational cost
6. Recommend: logical replication, with step-by-step plan
```

### Debugging

```
1. Symptom: API returns 502 intermittently at ~3am
2. What's known: DB metrics clean, app logs clean, upstream logs dropping
3. Hypothesis A: TLS cert rotation → refuted, cert valid through Dec
4. Hypothesis B: connection pool exhaustion → refuted, pool stats stable
5. Hypothesis C: network-level MTU issue → plausible, matches timing
6. Next step: packet capture during next occurrence
```

## Pitfalls

- **Performative reasoning.** Don't use it to look thorough. Use it when the problem genuinely needs it.
- **Over-branching.** Two or three branches is often enough. Exploring every possibility exhausts the budget.
- **Ignoring revision.** If a step turns out wrong, explicitly revise — don't just continue as if the prior step was right.
- **Conclusion drift.** End with a concrete answer, not "this requires more thought". If it does, say what specifically is missing.

## Output etiquette

- Show the final conclusion clearly — don't make the user read the whole chain to find the answer.
- Summarize the chain only if the user asks. By default, present the result.
- Keep each thought compact — 1–3 sentences. Long thoughts mean you're thinking about multiple things at once; split them.
