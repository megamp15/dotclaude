---
source: core
name: llm-serving
description: Self-hosted LLM serving — pick the right runtime (Ollama / vLLM / llama.cpp / TGI), pick the right model format (gguf / safetensors / AWQ / GPTQ), size GPU memory honestly, run models without silently falling off a cliff. Use when the user asks about running an LLM locally, choosing a serving stack, or why their model is slow / OOM'ing / giving garbage.
triggers: ollama, vllm, llama.cpp, tgi, text-generation-inference, gguf, safetensors, awq, gptq, quantize, quantization, kv cache, continuous batching, paged attention, local llm, self-host llm, inference server, model serving, cuda oom, vram, bitsandbytes
---

# llm-serving

Domain hub for running LLMs yourself. Claude should load this skill
when a question touches model serving, quantization, hardware sizing,
or inference runtime selection.

The purpose is to prevent three common failure modes:

1. **Wrong runtime for the job** — running `llama.cpp` for a high-throughput API, or `vLLM` for a desktop chatbot. Both work; only one is right.
2. **Silent quantization damage** — taking a model from full precision to Q2 and wondering why it now hallucinates. Quantization is a trade; the trade must be explicit.
3. **OOM on the wrong token** — sizing VRAM for weights only and ignoring KV cache, activations, and batch. OOM at token 2000 of a 32k context is the classic version.

## When to use this skill

- "Which should I use, Ollama or vLLM?"
- "How much VRAM do I need for a 70B model?"
- "Why is my throughput so low?"
- "Is Q4 good enough for my use case?"
- "How do I serve multiple models on one GPU?"
- "My model works in Ollama but fails in vLLM — why?"

## Decision workflow

For any serving question, walk the user through these in order:

### 1. What's the workload?

Ask (or infer) one of:

- **Single-user chat** (you + maybe a few friends) → Ollama, LM Studio, or llama.cpp direct.
- **API for an app** (10-100 concurrent users) → vLLM if GPU-resident, llama.cpp server for CPU or hybrid.
- **High-throughput production** (100+ concurrent, SLAs) → vLLM or TGI; consider batching-aware front-end.
- **Batch scoring** (embarrassingly parallel, non-interactive) → vLLM batch mode, or a distributed runner.
- **Embeddings only** → different tool entirely — `text-embeddings-inference`, `sentence-transformers`, or model-native embedding endpoints. Don't use a chat-tuned model for embeddings.

Runtime comparison lives in `references/serving-options.md`.

### 2. What hardware?

Get honest answers before proceeding:

- GPU model + VRAM (e.g., "RTX 4090, 24 GB" or "2x A6000, 48 GB each")
- CPU RAM
- Whether multi-GPU is an option
- Whether CPU-only is acceptable

Common mistake: assuming 24 GB VRAM = can serve a 24B model. It can't — not without quantization and not without leaving room for KV cache.

Sizing math lives in `references/memory-and-batching.md`.

### 3. What model + format?

- **Base model**: Llama 3.1, Qwen 2.5, Mistral, Gemma 2, etc. — pick by license, context length, benchmark fit.
- **Size**: 7B / 13B / 34B / 70B / 405B. Bigger isn't automatically better for the user's use case — eval on their task.
- **Format**: `gguf`, `safetensors`, `AWQ`, `GPTQ`, etc. Runtime and hardware constrain this.
- **Quantization level**: FP16 / Q8 / Q6 / Q5_K_M / Q4_K_M / Q3_K_S / Q2. Lower = smaller + faster + dumber. See `references/model-formats.md`.

### 4. Sanity-check the plan

Before the user starts downloading 40 GB of weights:

- Weights fit in VRAM at chosen quant? (weights_GB × 1.1 for overhead, then + KV cache for chosen context × batch).
- Runtime supports the chosen format? (vLLM ≠ gguf; Ollama = gguf).
- Context length × batch × model size fits the planned KV cache?
- License matches intended use? (Llama 3.x non-commercial tiers, Qwen licenses, Gemma terms).

If any fail, say so *before* the 40 GB download.

## Common failure patterns (fast triage)

| Symptom | First suspect | Where to look |
|---|---|---|
| `CUDA out of memory` at startup | Model doesn't fit. Weights + ~10-15% overhead | `memory-and-batching.md` sizing |
| OOM after N tokens | KV cache scaling with context × batch | same — KV cache section |
| Throughput << expected on vLLM | `gpu_memory_utilization` too low, or no continuous batching enabled | `serving-options.md` vLLM section |
| Model "feels dumb" after quantizing | Q2/Q3 damage; try Q4_K_M or Q5_K_M minimum | `model-formats.md` quant ladder |
| Model works in Ollama, fails in vLLM | Format mismatch (gguf vs safetensors/AWQ/GPTQ) | `model-formats.md` |
| Streaming chokes under load | Single-threaded runtime or no async handling | `serving-options.md` concurrency notes |
| Multi-GPU not helping | Tensor parallel not configured, or model small enough it shouldn't split | `memory-and-batching.md` multi-GPU |

## Reference guide

| Topic | Reference |
|---|---|
| Runtime selection: Ollama, vLLM, llama.cpp, TGI, SGLang | `references/serving-options.md` |
| Model formats + quant levels: gguf, safetensors, AWQ, GPTQ | `references/model-formats.md` |
| VRAM math, KV cache, batching, multi-GPU | `references/memory-and-batching.md` |

## What this skill does NOT cover

- Training or fine-tuning (different domain; LoRA, full FT, RLHF).
- Embedding model deployment (use `text-embeddings-inference`).
- Cloud API services (OpenAI, Anthropic, Gemini, etc.) — that's API integration, not serving.
- Agent frameworks / RAG pipelines — separate concerns.
- Prompt engineering for the served model — not a serving problem.

## Do not

- Do not recommend a quantization level without asking about the use case.
  Q4_K_M is fine for coding; it may not be fine for math or tool-use accuracy.
- Do not assume a runtime supports a format — verify. vLLM, Ollama, and llama.cpp each support different formats.
- Do not give hardware advice without knowing the model size and context length. "Will it fit on a 4090?" has no answer without both.
- Do not optimize for raw TPS (tokens per second) without knowing whether the user cares about latency, throughput, or cost per token. Different targets, different setups.
- Do not recommend running untrusted model weights without warning about supply-chain risk. `safetensors` is safer than `pickle`-based formats.
