# When to fine-tune

## The decision tree

```
Is the issue about output style / format / tone?
  → Try prompting first. If the model can do it with the right
    prompt but you want consistency → fine-tune.

Is the issue missing or changing knowledge?
  → RAG. Fine-tuning for knowledge is expensive and brittle.

Is the issue task-specific behavior (classify, extract, translate)?
  → Fine-tune. Narrow tasks respond best.

Is the issue "safety" / refusal patterns / persona?
  → Fine-tune (SFT + DPO). Prompts work but are bypassable.

Is the issue latency / cost at scale?
  → Fine-tune a smaller model to match a larger one's behavior on
    your task (model distillation via FT).

Is the issue "the model gets it wrong sometimes"?
  → Diagnose first. Probably prompting or retrieval, not FT.
```

## What fine-tuning does well

- **Format / style consistency** — always respond in JSON, always
  use a specific tone.
- **Task specialization** — structured extraction, classification,
  code generation in a specific framework.
- **Alignment to preferences** — DPO on human preferences shapes
  which response is preferred among candidates.
- **Distillation** — teach a small model to behave like a big one
  on your task.
- **Domain vocabulary** — medical, legal, internal jargon (usually
  best combined with RAG).
- **Reduced prompt length** — behaviors baked into weights mean
  shorter prompts → lower cost / latency per request.

## What fine-tuning does badly

- **Adding new facts.** Models are bad at remembering training
  facts; they hallucinate variants. Use RAG.
- **Rapidly changing knowledge.** Every update requires retraining.
- **Replacing business logic.** "Always return price × 1.2" — just
  code it.
- **Long-context comprehension.** FT mostly preserves base-model
  capabilities; it doesn't add them.
- **Critical reasoning paths.** FT can subtly break the model's
  ability to handle edge cases.
- **Safety guarantees.** FT helps; doesn't replace policy /
  guardrails.

## Cost comparison

Rough orders of magnitude for a 7B base model:

| Method | Compute | Iteration speed | Cost (USD) |
|---|---|---|---|
| Prompt eng | None | Minutes | $0 |
| Few-shot + RAG | None | Minutes | $0 |
| LoRA / QLoRA FT | 1 GPU-hour | Hours | $1–10 |
| Full FT (7B) | 4–8 GPU-hours | Half-day | $20–80 |
| Full FT (70B) | Many-GPU day | 1–2 days | $500–2000 |
| OpenAI / Bedrock hosted | - | Hours | $10–1000+ by volume |

Add serving cost: adapters don't add much; serving a custom
merged 70B costs whatever your GPU time costs.

## Knowledge vs. behavior

A useful distinction:

- **Knowledge** — "the CEO's name is X", "the SKU for this is Y".
  FT stores this poorly; model may hallucinate variants or
  outdate. → RAG.
- **Behavior** — "always answer in this format", "refuse requests
  about X", "use my internal API conventions". FT stores this
  well. → fine-tune.

Try: put knowledge in retrieval, put behavior in weights.

## Instruction tuning vs. base model

**Instruction-tuned ("instruct")** models (Llama-3.1-Instruct,
Mistral-Instruct) are already fine-tuned for helpful chat. Start
from these unless:

- You want full control over chat template.
- You're doing continued pretraining.
- The base model performs better on your benchmark than instruct.

Most teams should start from an Instruct checkpoint.

## Continued pretraining

Very different from SFT / instruction-tuning:

- Data is unstructured text; no question/answer pairs.
- Objective is predicting the next token on your domain corpus.
- Outcome is a new base model with shifted distributional
  understanding.

Only do this if:

- You have a large corpus (hundreds of millions of tokens+).
- The domain vocabulary is truly different (ancient languages,
  novel programming languages, proprietary formats).
- You can afford the compute (many GPUs for many days).

For most teams, this is not the right tool. SFT on 1k–10k quality
examples is enough.

## Data readiness checklist

Before starting any fine-tune, confirm:

- [ ] You have **example inputs and desired outputs** for the task.
- [ ] You have at least **500 clean examples** (10k+ ideal for
      hosted, 1k+ for LoRA).
- [ ] You have a **held-out eval set** (100+ examples) the model
      never sees during training.
- [ ] You have a **pass/fail or numeric** metric that tracks what
      you care about.
- [ ] You have a **baseline** — the untuned model's score on the
      eval.
- [ ] Data is **deduped** (no test leakage into train).
- [ ] Data is **licensed** for your use (no scraping that violates
      ToS).
- [ ] Data is **de-identified** if it contains PII.

Missing any of these → halt and fix first.

## Data format common shapes

**Alpaca-style:**

```json
{"instruction": "Translate to French", "input": "Hello", "output": "Bonjour"}
```

**ShareGPT / conversations:**

```json
{"messages": [
  {"role": "system", "content": "You are a helpful assistant."},
  {"role": "user", "content": "Translate hello to French"},
  {"role": "assistant", "content": "Bonjour"}
]}
```

Most frameworks accept both; ShareGPT format is more flexible (multi-
turn, tools). The chat template turns messages into the raw text
the model saw at pretraining — mismatch here = bad model.

## Preference data (for DPO / ORPO / KTO)

```json
{
  "prompt": "...",
  "chosen": "response I prefer",
  "rejected": "response I don't prefer"
}
```

Source ideas:

- Human-rated pairs (most expensive, best quality).
- "Constitutional AI" style: one model generates N responses, a
  second model ranks.
- Production logs: user accepted vs. user edited/re-prompted.

Size: 1k–10k pairs for a noticeable DPO effect; 10k+ for more
stable.

## Quality over quantity

Published studies (LIMA, Zephyr β) consistently show:

- 1k high-quality examples often beat 100k mediocre ones.
- Diverse, clean examples matter more than raw volume.
- Human review of a sample is the single most impactful
  intervention.

Dataset red flags:

- Duplicate or near-duplicate rows.
- Format inconsistencies (same task, different output styles).
- Incorrect labels.
- PII / copyrighted content.
- Model-generated data without filtering (error amplification).

## Hosted vs. self-host fine-tuning

**Hosted (OpenAI / Anthropic / Bedrock / Vertex):**

- Pro: no infra, straightforward.
- Pro: often gets newest models.
- Con: can't inspect the model; often can't share or deploy
  elsewhere.
- Con: expensive at volume.
- Con: vendor lock-in.
- Con: limited method choice (usually just SFT, sometimes DPO).

**Self-host (Unsloth, Axolotl, TRL):**

- Pro: full control; any method; any serving.
- Pro: cheap per-run at moderate scale.
- Pro: model is yours.
- Con: GPU management.
- Con: evaluation / MLOps on you.

Default: **start hosted** to prove the approach; **move self-host**
when you're doing it repeatedly or at scale.

## Common failure modes

- **Catastrophic forgetting** — model loses capabilities. Mitigate
  with LoRA (smaller weight change), mix in general data (5-20% of
  training set), train fewer epochs.
- **Mode collapse** — model produces only one style of output.
  Often from overfitting on homogeneous data.
- **Spurious memorization** — model regurgitates training examples.
  Dedupe, diversify, evaluate on held-out.
- **Alignment tax** — alignment / refusal tuning reduces benchmark
  scores. Measure it; decide if it's acceptable.
- **Silent chat-template mismatch** — training template ≠ serving
  template → garbage responses. Audit both sides.
