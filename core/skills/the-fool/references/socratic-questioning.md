---
source: core
ported-from: https://github.com/Jeffallan/claude-skills/blob/main/skills/the-fool/references/socratic-questioning.md
ported-at: 2026-04-17
adapted: true
---

# Socratic questioning

The Socratic mode does not argue. It asks. The goal is to help the user
discover gaps in their own reasoning by surfacing what they haven't examined.
Every question should produce a moment of "I hadn't thought about that."

## Core principle

Arguing produces defense. Questioning produces reflection. Choose questions
that make the person genuinely reconsider — not questions designed to
"catch" them.

## Question categories

### 1. Definitional — challenge vague or overloaded terms

| Pattern | Example |
|---|---|
| "When you say X, what specifically do you mean?" | "When you say 'scalable', 10× or 1000×?" |
| "How would you define X to someone unfamiliar?" | "Explain 'real-time' in one sentence to a PM." |
| "Does X mean something different here than elsewhere?" | "Is 'fast' the same for the API and the nightly batch?" |

### 2. Evidential — probe the basis for beliefs

| Pattern | Example |
|---|---|
| "What evidence supports this?" | "Which user research shows this?" |
| "How do you know X is true?" | "How do we know the current system can't handle it?" |
| "What would change your mind?" | "What metric would convince you this is the wrong approach?" |
| "Data or intuition?" | "Is 'users hate the current flow' from research, or a hallway anecdote?" |

### 3. Logical — test the reasoning chain

| Pattern | Example |
|---|---|
| "Does X necessarily lead to Y?" | "Does caching necessarily improve UX here?" |
| "What assumptions connect X to Y?" | "What must be true for microservices to improve velocity?" |
| "Could the opposite also be true?" | "Could a monolith actually ship faster in this case?" |
| "Correlation vs. causation?" | "Did the refactor cause the improvement, or was it the new hire?" |

### 4. Perspective-shifting — force other viewpoints

| Pattern | Example |
|---|---|
| "How would [stakeholder] see this?" | "How does the on-call engineer feel about this architecture?" |
| "What would a senior skeptic say?" | "What would a senior engineer who prefers simplicity say?" |
| "How does this look in 2 years?" | "Will this abstraction still make sense when the team doubles?" |
| "Who loses if this succeeds?" | "If we adopt this vendor, what capability do we give up?" |

### 5. Consequential — trace the implications

| Pattern | Example |
|---|---|
| "What happens next?" | "After we migrate, what's the first thing that breaks?" |
| "Second-order effect?" | "If we hire contractors, what happens to team knowledge?" |
| "Cost of being wrong?" | "If this assumption is wrong, how bad is recovery?" |
| "What becomes harder later?" | "What future feature becomes harder if we choose this schema?" |

## Assumption detection signals

Listen for the words that hide assumptions:

| Phrase | Assumption underneath |
|---|---|
| "Obviously…" | Not examined |
| "Everyone knows…" | Consensus not verified |
| "It just makes sense…" | Reasoning not articulated |
| "We always…" | History assumed optimal |
| "There's no other way…" | Alternatives not explored |
| "It's simple…" | Complexity underestimated |
| "Users want…" | Research may be absent or stale |
| "The standard approach is…" | Convention not validated for context |

Mark each occurrence; that's a candidate for a probing question.

## Domain-adapted question banks

### Technical decisions

- What are you optimizing for? Are you sure that's the right dimension?
- What's the simplest version that tests the core assumption?
- What constraint are you treating as fixed that might actually be flexible?
- How would you build this if you had to ship in one week?
- What's the most expensive thing to change later?

### Product / business decisions

- Who is the customer for this decision? Are you sure?
- What would make this a bad investment in hindsight?
- How does this compare to doing nothing?
- What's the opportunity cost?
- If a competitor made the opposite choice, would you be worried?

### Strategic decisions

- What has to be true for this strategy to work?
- Which of those assumptions are you least confident about?
- What's the fastest way to test the riskiest assumption?
- How will you know if this is failing, before it's too late?
- What's the exit strategy if this doesn't work?

## Output template

```markdown
## Socratic analysis: <target>

### Assumption inventory
| # | Assumption | Type | Confidence |
|---|---|---|---|
| 1 | [Stated or hidden] | Stated / Unstated | High / Med / Low |

### Probing questions (by theme)

**Theme 1: [e.g., "User behavior"]**
1. [Question targeting assumption #X]
2. [Follow-up deepening the probe]

**Theme 2: [e.g., "Technical feasibility"]**
1. …

### Suggested experiments
| Assumption | Experiment | Effort | Signal |
|---|---|---|---|
| [Riskiest] | [How to test cheaply] | Low/Med/High | [What result means] |
```

## Anti-patterns

- Leading questions ("You agree it would be better to…?"). If it's an
  opinion, just say it.
- Rapid-fire questioning — asking 15 questions at once. Three good questions
  beat fifteen weak ones.
- Sophistry — questioning to win, not to illuminate.
- Questioning well-established conventions ("Why use TLS?") when the real
  question is elsewhere.
