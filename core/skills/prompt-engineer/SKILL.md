---
name: prompt-engineer
description: Prompt design for production LLM systems — structured prompts, few-shot, chain-of-thought, self-consistency, tool use, output schemas / JSON mode, evals for prompts, model-specific idioms (Anthropic XML, OpenAI function calling), prompt caching. Distinct from `rag-architect`, `fine-tuning-expert`, and casual "prompt hacks".
source: core
triggers: /prompt-engineer, prompt engineering, system prompt, few-shot, chain of thought, CoT, self-consistency, tool use, function calling, JSON mode, structured output, prompt injection, prompt caching, XML prompts, ReAct
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/prompt-engineer
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# prompt-engineer

Deep prompt engineering for production LLM systems — not "growth-
hack" prompts, but structured, testable prompts with evaluation
gates and defensive design against injection.

> **See also:**
>
> - `core/skills/rag-architect/` — retrieval complements prompting
> - `core/skills/fine-tuning-expert/` — when prompting plateaus
> - `core/rules/llm-safety.md` — safety + output handling baseline
> - `core/skills/llm-serving/` — inference infra knobs (temperature,
>   max tokens, caching)

## When to use this skill

- Designing a system prompt for a new LLM-backed feature.
- Improving reliability / format compliance of an existing prompt.
- Choosing between zero-shot, few-shot, and CoT.
- Wiring tool use / function calling.
- Defending against prompt injection.
- Reducing token / latency cost without hurting quality.
- Building a prompt-level eval and regression gate.

## References (load on demand)

- [`references/prompt-patterns.md`](references/prompt-patterns.md)
  — structure (role, task, context, format, examples), few-shot
  and CoT selection, self-consistency, ReAct, tool use, output
  schemas, model-specific idioms (Anthropic XML, OpenAI functions,
  Gemini).
- [`references/injection-and-evals.md`](references/injection-and-evals.md)
  — prompt injection taxonomy + defenses (trust boundaries,
  delimiters, allowlists, canary tokens), eval harness for
  prompts, A/B testing, prompt caching strategies.

## Core workflow

1. **Write the eval first.** 10–30 representative inputs with
   desired outputs. Without this, every change is a guess.
2. **Start simple.** Zero-shot + clear instructions. Only add
   complexity (CoT, few-shot, examples) when the eval says you
   need it.
3. **Separate untrusted content.** Structured delimiters (XML
   tags, JSON). Never "merge" system and user text without
   barriers.
4. **Constrain output.** JSON schema, allowed values,
   function-call signatures. Parse and retry on failure.
5. **One variable at a time.** Changing the prompt *and* the model
   *and* the temperature at once makes attribution impossible.
6. **Use the model's native idioms.** XML for Claude, tools for
   OpenAI, structured output for Gemini.
7. **Measure and ship.** Promote the winning variant through
   configuration — don't leave every prompt inline.

## Defaults

| Question | Default |
|---|---|
| Temperature (production) | 0.0 unless randomness is required |
| Max tokens | Set explicitly, tight as possible |
| Top-p | 1.0 (don't combine with temperature 0) |
| System prompt role | Always used; holds instructions + format |
| User prompt role | Untrusted content; include via delimiters |
| Structure | XML tags for Claude; sections + markdown for others |
| Few-shot | 2–5 examples; more rarely helps |
| CoT | Only when task requires reasoning; prefer `<thinking>` tags |
| Output | JSON with schema validation + retry on parse error |
| Stop sequences | Set where appropriate to bound output |
| Prompt caching | Use when supported; cache the stable system prefix |
| Versioning | Store prompts in repo; tag by semver; log version per request |

## Anti-patterns

- **"Please think carefully" padding.** Modern models don't need
  it; it eats tokens without measured gains.
- **Prompt injection ignorance.** Treating user text as
  instructions is how your assistant leaks secrets.
- **Ad-hoc prompt edits in UI, not in code.** Prompt = code. Git.
- **No eval.** "It worked in my demo" → regressions ship silently.
- **Temperature > 0 in production** for deterministic tasks.
- **Asking the model to follow a JSON schema in prose** instead of
  using the platform's structured output / JSON mode.
- **Single megaprompt** doing three tasks. Chain or split into
  separate calls.
- **Overfitting to your dev examples.** Eval set must be
  representative, not the ones you tuned against.
- **Silently upgrading model versions** — a new Sonnet/GPT can
  shift behavior. Pin versions; evaluate upgrades.

## Output format

For a prompt design:

```
Task:             <one-sentence>
Input:            <shape + constraints>
Output:           <schema + example>
Success criteria: <eval metric + threshold>

System prompt:
  ```
  <the prompt>
  ```

Few-shot examples:  <N; in-prompt or sibling tool call>

Tools / functions:  <JSON schemas if any>

Model:              <name + version>
Temperature:        <value>
Max tokens:         <value>
Stop sequences:     <if any>
Caching:            <what is cached>

Eval set:           <path + size + metrics>
Baseline:           <prior version's score>
This version:       <score>

Known failure modes: <list>
```

For a prompt improvement:

```
Before: <diff-able current prompt>
After:  <proposed prompt>

Eval delta:
  Metric A:   <old> → <new>
  Metric B:   <old> → <new>
  Latency:    <old> → <new>
  Tokens:     <old> → <new>

Justification:  <why this should be merged>
Risks / out-of-scope: <what we didn't try>
```

## Model idioms — quick reference

| Model family | Idiom |
|---|---|
| **Anthropic Claude** | XML tags (`<instructions>`, `<context>`, `<example>`); system in `system:` param; `<thinking>` for CoT |
| **OpenAI GPT** | Messages API with roles; **function calling / tools** for structured output; JSON mode as fallback |
| **Google Gemini** | System instructions + structured output via `response_schema` + JSON; function calling |
| **Meta Llama** | Llama-3 chat template; use Instruct variants; system role is supported |
| **Mistral** | `<s>[INST]` template; system prompts via prepend |
| **Cohere Command R** | Strong RAG-grounded generations with `documents` parameter |

Use each model's native structured-output feature where available.
Don't rely on "respond in JSON" in the prompt alone — retry-loops
are expensive and flaky.

## The "prompt is code" principle

- Prompts live in `prompts/` under source control.
- Versioned (`greeting-v3.md`) and referenced by ID.
- Code loads by ID; production config picks the version.
- Changes go through PR review.
- Evals run in CI; PRs blocked if eval regresses.

Without this, your prompt system decays into a liability.
