# Training recipes

## SFT (Supervised Fine-Tuning)

The workhorse. Teach the model to map prompts to desired responses.

```
loss = -log P(desired_output | prompt, previous_tokens)
```

### Recipe (QLoRA, Unsloth, 7–8B model)

```yaml
# axolotl-style config
base_model: meta-llama/Llama-3.1-8B-Instruct
model_type: LlamaForCausalLM
tokenizer_type: AutoTokenizer

load_in_4bit: true
adapter: lora
lora_r: 16
lora_alpha: 32
lora_dropout: 0.05
lora_target_modules:
  - q_proj
  - k_proj
  - v_proj
  - o_proj
  - gate_proj
  - up_proj
  - down_proj

datasets:
  - path: data/train.jsonl
    type: chat_template

chat_template: llama3

sequence_len: 4096
sample_packing: true
pad_to_sequence_len: true

learning_rate: 2e-4
lr_scheduler: cosine
warmup_steps: 10
num_epochs: 3
micro_batch_size: 4
gradient_accumulation_steps: 4
optimizer: paged_adamw_8bit

eval_steps: 50
save_steps: 100
save_total_limit: 3
```

### Recipe (Unsloth Python)

```python
from unsloth import FastLanguageModel
from trl import SFTTrainer

model, tokenizer = FastLanguageModel.from_pretrained(
    model_name="unsloth/llama-3.1-8b-instruct-bnb-4bit",
    max_seq_length=4096,
    load_in_4bit=True,
)

model = FastLanguageModel.get_peft_model(
    model,
    r=16,
    lora_alpha=32,
    target_modules=["q_proj", "k_proj", "v_proj", "o_proj",
                    "gate_proj", "up_proj", "down_proj"],
    lora_dropout=0.05,
    use_gradient_checkpointing="unsloth",
)

trainer = SFTTrainer(
    model=model,
    tokenizer=tokenizer,
    train_dataset=ds,
    max_seq_length=4096,
    args=TrainingArguments(
        per_device_train_batch_size=4,
        gradient_accumulation_steps=4,
        learning_rate=2e-4,
        num_train_epochs=3,
        warmup_steps=10,
        lr_scheduler_type="cosine",
        optim="paged_adamw_8bit",
        eval_steps=50,
        save_steps=100,
        output_dir="out",
    ),
)
trainer.train()
```

### Key hyperparameters

- **Learning rate** — 2e-4 for LoRA is a standard start. Full FT:
  1e-5 to 5e-5.
- **Epochs** — 2–3 for moderate datasets; 1 for large (50k+).
- **Warmup** — 3–5% of total steps.
- **LR schedule** — cosine with warmup is the default.
- **Batch size (effective)** — 32–128. Use gradient accumulation to
  reach target.
- **Max seq len** — set to what your data needs. Longer = more
  memory.
- **Sample packing** — pack multiple examples per sequence to
  reduce padding; 2–3× throughput.
- **Gradient checkpointing** — reduces memory, slows training ~20%.
  Turn on for tight memory budgets.

## LoRA / QLoRA / DoRA (PEFT)

**PEFT** = Parameter-Efficient Fine-Tuning. Only train small
adapter weights while freezing the base model.

### LoRA

- Injects rank-decomposition matrices into linear layers:
  `W' = W + A*B` where A is `d×r`, B is `r×d`.
- Only A, B are trained; tiny (< 1% of params).
- Outputs: adapter that can be merged back or loaded separately.
- `r` (rank) trades capacity for compute. Start 16; 32 for more
  capacity; 64 rarely needed.
- `alpha` scales the update; convention: `alpha = 2*r`.

### QLoRA

- LoRA + 4-bit quantized base weights. Lets you fine-tune 7B on a
  single consumer GPU.
- **NF4 quantization** — normal-float 4-bit, optimal for weights.
- **Double quantization** — quantize the quantization constants.
- **Paged optimizers** — offload optimizer states to CPU on
  spikes.

Use QLoRA by default unless you have A100s+.

### DoRA

- Decomposes weight update into magnitude + direction; fine-tunes
  both.
- ~10% better than LoRA on many tasks at similar rank.
- Slightly slower.
- Enable with `use_dora: true` in recent frameworks.

### Target modules

Default: **all linear layers** (`q_proj`, `k_proj`, `v_proj`,
`o_proj`, `gate_proj`, `up_proj`, `down_proj` for Llama-style
models). Using a subset saves memory but costs quality.

## DPO (Direct Preference Optimization)

Align model to human preferences without a reward model.

- Input: `(prompt, chosen_response, rejected_response)` triples.
- Loss: boost probability of chosen relative to rejected, weighted
  by a KL regularizer against the reference model.

### Recipe (TRL)

```python
from trl import DPOTrainer, DPOConfig

trainer = DPOTrainer(
    model=sft_model,
    ref_model=None,   # auto-creates frozen copy of sft_model
    train_dataset=preference_ds,
    tokenizer=tokenizer,
    args=DPOConfig(
        beta=0.1,                     # KL strength
        learning_rate=5e-7,           # MUCH lower than SFT
        num_train_epochs=1,
        per_device_train_batch_size=2,
        gradient_accumulation_steps=8,
        lr_scheduler_type="cosine",
        optim="paged_adamw_8bit",
    ),
)
trainer.train()
```

### Key points

- **SFT first, then DPO.** DPO on a base model is unstable.
- **LR is 1/100th of SFT.** 5e-7 to 5e-6.
- **One epoch** is usually enough.
- **Beta (KL)** — 0.1 default. Lower → more aggressive preference
  fitting; higher → stays closer to reference.

## ORPO

Odds Ratio Preference Optimization — combines SFT + DPO in a
single loss. No SFT phase needed.

- Loss: SFT on chosen + log-odds penalty on rejected.
- One-stage training saves compute.
- Results competitive with SFT → DPO.

Use when you have preference data from scratch and want a single
training run.

## KTO (Kahneman-Tversky Optimization)

Same goal as DPO but needs only `(prompt, response, liked?)` binary
labels — no pair comparisons.

- Easier to label in production (thumbs up / down).
- Looser requirements on data; suitable for partial labels.
- Slightly less efficient than DPO per-example with preference
  pairs.

## RLHF (full)

Classic: reward model + PPO. Complex, unstable, compute-heavy.
Most teams don't need this anymore — DPO / ORPO / KTO get close.

Only consider when:

- You have a strong reward model already.
- DPO results plateau.
- You have the budget and team.

## Evaluation

### At training time

- Log loss + validation loss every N steps.
- Save best validation checkpoint.
- Sample a few completions from the eval set; read them.

### After training

- Re-run your offline eval set.
- Compare to baseline (untuned model).
- Spot-check on held-out real queries.
- Run a generic benchmark sample (MMLU subset, HumanEval subset) to
  catch regressions.

### Eval frameworks

- **lm-evaluation-harness** — big battery of benchmarks.
- **OpenCompass** — alternative.
- **Ragas / DeepEval** — LLM-as-judge evals.
- **Promptfoo** — quick CLI evaluator for prompts/models.
- **Custom scripts** — usually necessary for domain-specific.

### Catching degradation

Include in eval:

- Your task-specific metric (what you optimized for).
- Generic capability sample (MMLU, HellaSwag, TruthfulQA subset).
- Safety / refusal checks (model still refuses harmful requests).
- Latency / throughput (fine-tuning shouldn't hurt these unless
  rank is huge).

## Quantization for serving

After training, quantize for cheaper serving:

- **AWQ** — activation-aware weight quantization; high quality at
  4-bit.
- **GPTQ** — post-training quantization; mature.
- **bitsandbytes NF4** — dynamic, simple; quality OK.
- **GGUF** (llama.cpp) — for CPU / mixed inference; Ollama uses it.

Rule of thumb:

- 16-bit → 8-bit: minimal quality loss, 2× smaller.
- 8-bit → 4-bit: small quality loss, 4× smaller. Good default.
- 4-bit → 2-bit: noticeable degradation. Skip unless forced.

## Packaging for serving

### Adapter only

- Ship the base model + the LoRA adapter.
- Load adapter at runtime.
- Pro: one base, many adapters; multi-tenant fine-tunes.
- Con: small latency overhead; depends on server support.

### Merged weights

- `model = model.merge_and_unload()` — bakes adapter into base.
- Pro: no adapter overhead; compatible with any server.
- Con: committing to this fine-tune; separate model file per tune.

### With vLLM / TGI

- **vLLM** — supports LoRA adapters at serve time
  (`--enable-lora`). Merged weights also work.
- **TGI** (Text Generation Inference) — similar; `--lora-adapters`.
- **Ollama** — use GGUF exports (merged + quantized).

## Continued evolution

Expect your fine-tune to go stale:

- Base models improve; consider re-fine-tuning the new base.
- Your data distribution shifts; refresh training data.
- Plan a quarterly "rebuild": re-train, re-eval, decide to deploy.

## Tooling quick reference

| Tool | Strength |
|---|---|
| **Unsloth** | Fastest OSS FT; nice defaults; single-GPU focus |
| **Axolotl** | Config-driven; popular; many methods |
| **HuggingFace TRL** | Reference implementations of SFT / DPO / PPO / ORPO / KTO |
| **torchtune** | PyTorch-official; minimal; production-clean |
| **Llama Factory** | GUI-ish; experimentation-friendly |
| **OpenAI fine-tuning** | Hosted SFT; no infra |
| **Bedrock / Vertex** | Managed hosted fine-tuning |

Start with Unsloth or Axolotl for self-host; TRL if you need
something that's not packaged.
