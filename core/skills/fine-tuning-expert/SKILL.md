---
name: fine-tuning-expert
description: LLM adaptation — when to fine-tune vs. prompt / RAG, dataset curation, SFT / DPO / ORPO / KTO, PEFT (LoRA, QLoRA, DoRA), framework choice (Unsloth, Axolotl, HF TRL, torchtune), evaluation, quantization, and serving with merged / adapter weights. Distinct from `rag-architect` (retrieval), `prompt-engineer` (prompts), `llm-serving` (inference infra).
source: core
triggers: /fine-tune, fine-tuning, SFT, instruction tuning, LoRA, QLoRA, DoRA, DPO, ORPO, KTO, RLHF, PEFT, Unsloth, Axolotl, TRL, torchtune, dataset curation for fine-tuning, Alpaca format, ShareGPT format, gradient accumulation, 4-bit training, merge adapter
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/fine-tuning-expert
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# fine-tuning-expert

Deep expertise on adapting pretrained LLMs to your domain or task.
Activates when the question is "should we fine-tune?" or "how do
we fine-tune?".

> **See also:**
>
> - `core/skills/rag-architect/` — retrieval is often cheaper and
>   better than fine-tuning for knowledge tasks
> - `core/skills/prompt-engineer/` — prompt-side first; fine-tune
>   only after prompt techniques plateau
> - `core/skills/llm-serving/` — inference infra (vLLM, TGI, Ollama)
> - `core/skills/ml-pipeline/` — pipeline and MLOps patterns

## When to use this skill

- Deciding whether fine-tuning or prompting/RAG fits your problem.
- Preparing a fine-tuning dataset from raw data.
- Picking SFT vs. DPO / ORPO / KTO; LoRA vs. QLoRA vs. full.
- Choosing a framework (Unsloth / Axolotl / TRL / torchtune).
- Configuring the training run (LR, batch, epochs, target
  modules).
- Evaluating fine-tuned models and avoiding overfit / regressions.
- Packaging and serving adapters vs. merged weights.

## References (load on demand)

- [`references/when-to-fine-tune.md`](references/when-to-fine-tune.md)
  — decision tree (prompt → RAG → fine-tune), capabilities you
  can and can't unlock via FT, cost comparison.
- [`references/training-recipes.md`](references/training-recipes.md)
  — SFT, DPO, ORPO, KTO explained; PEFT methods (LoRA, QLoRA,
  DoRA); hyperparameters and starting points; evaluation.

## Core workflow

1. **Exhaust prompting + RAG first.** Fine-tuning is expensive,
   inflexible, and risks regressions. Most "we need to fine-tune"
   requests are solvable with better prompts or retrieval.
2. **Define success upfront.** What metric moves? Offline eval set
   frozen before training starts. Ideally pass-fail threshold.
3. **Curate the dataset.** Quality > quantity. 1,000 clean examples
   beat 10,000 noisy ones. Aim for the *behaviors* you want, not
   just the *answers*.
4. **Start small.** LoRA / QLoRA on a smaller base model; iterate
   fast; scale up only when the recipe is stable.
5. **Hold out a real test set.** Not seen in training. Not seen in
   hyperparameter tuning. Only used at the end.
6. **Check regressions.** Fine-tuning can make the model worse at
   things you didn't test. Include generic benchmarks (MMLU sample,
   your pre-fine-tune eval).
7. **Ship as an adapter** if possible; merge only when serving
   infra requires it.

## Defaults

| Question | Default |
|---|---|
| Base model (open) | Llama 3.1/3.3, Qwen 2.5, Mistral / Mixtral, Gemma 2 |
| Base model (hosted fine-tune) | OpenAI `gpt-4o-mini`, Anthropic Claude (when available), Bedrock |
| Method | SFT → DPO (if preference data) |
| PEFT | QLoRA (4-bit) unless specifically proven to underperform |
| Framework | Unsloth (fastest, OSS) or Axolotl (config-driven) |
| LoRA rank | r=16, alpha=32 (start); tune by eval |
| Target modules | All linear layers (`all-linear`) |
| Learning rate | 2e-4 (LoRA); 1e-5 (full FT) |
| Batch size | As big as fits; use gradient accumulation |
| Epochs | 2–3 for SFT; 1 for DPO |
| Max seq length | What your task needs; don't waste tokens |
| Eval frequency | Every N steps; save best-eval checkpoint |
| Dataset size (starter) | 1k–10k examples |
| Chat template | Match the base model's (critical!) |
| Quantization (serving) | 4-bit (awq / gptq / bnb) for single-GPU |

## Anti-patterns

- **Fine-tuning to add knowledge** — weak. RAG is better.
- **Fine-tuning on the test set** — common accident. Always
  dedupe + hold out.
- **Changing the chat template at serving time** — if you trained
  with one template and serve with another, quality collapses.
- **Massive LR or massive ranks** — destabilizes LoRA training;
  overfits fast.
- **One-epoch shortcut** — works for 10k+ examples; usually hurts
  small datasets.
- **No baseline** — if you don't compare against the untuned base
  model on the same eval, you don't know whether FT helped.
- **Training on "data augmentation" from the same model you're
  tuning** — amplifies the model's biases / hallucinations.
- **No regression test** — the model gets better at X, worse at
  Y. Detect both.
- **Ignoring cost of serving custom weights** — one more model to
  manage, version, monitor.

## Output format

For a "should we fine-tune?" question:

```
Problem:         <what does the model need to do?>
Tried already:   <prompt eng / RAG / tool use / routing>
Residual gap:    <what's still missing>

Verdict:         fine-tune | prompt | RAG | hybrid
Reason:          <1-3 lines>

If fine-tune:
  Base model:    <+ rationale>
  Method:        <SFT / DPO / both>
  PEFT:          <LoRA / QLoRA / full>
  Dataset:       <shape + size + source>
  Eval:          <metric + set + pass threshold>
  Cost estimate: <compute + $ per run>
  Infra:         <framework + where it runs>
```

For a training recipe:

```
Base:            <model + size + revision>
Framework:       <unsloth / axolotl / trl>
Data:            <path + format + size + split>
Chat template:   <format>
Method:          <SFT / DPO / ...>
PEFT:            <r, alpha, targets>
Hyperparameters: <lr, batch, accum, epochs, warmup, sched>
Eval:            <set + metric + cadence>
Save policy:     <best-eval / last>
Cost:            <wall-clock + $ estimate>
```

## Fine-tune vs. prompt vs. RAG — one-liner

- **Prompt** — make the model do the right thing by asking well.
  Cheap, flexible, fast to iterate.
- **RAG** — give the model the right facts at query time. Handles
  changing / private knowledge without retraining.
- **Fine-tune** — change the model's behavior / style / format /
  latent knowledge. Locks it in; serves faster per token.

Often the answer is **two of three**, not "one of three".
