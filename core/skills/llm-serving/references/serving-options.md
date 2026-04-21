# LLM serving runtimes — pick the right one

Each runtime optimizes for a different axis. Picking wrong makes
everything painful.

## Quick chooser

| Use case | First choice | Why |
|---|---|---|
| Desktop chat, 1 user | **Ollama** | Easiest. Model management built in. gguf native. |
| Coding in an IDE (local) | **Ollama** or **LM Studio** | Integrates with Continue, Cursor, etc. |
| CPU-only / mixed GPU-CPU | **llama.cpp** (server) | Best CPU inference; partial GPU offload. |
| Internal API, 10-100 users | **vLLM** | Continuous batching; massive throughput boost over naive serving. |
| High-throughput production | **vLLM** or **TGI** | PagedAttention; mature batching. |
| Structured output at scale | **SGLang** or **vLLM** + `guided_json` | Constrained decoding, JSON schema, regex. |
| Multi-model rapid swap | **Ollama** | Model pull / run is first-class. |
| Embeddings | **text-embeddings-inference** (HF) | Purpose-built; don't use a chat runtime. |

## Ollama

- **Strengths**: trivial UX (`ollama pull llama3.1; ollama run llama3.1`), model library, good default quantization (Q4_K_M), gguf native, works on CPU + GPU + Apple Silicon.
- **Weaknesses**: no continuous batching — bad choice for concurrent API load. Throughput collapses under parallel requests. No PagedAttention.
- **Format**: gguf only.
- **API**: OpenAI-compatible since late 2024; `/api/chat` and `/api/generate` native.
- **When it's wrong**: you're exposing it to anything beyond single-user workloads. Use it for yourself, not for the app.

## vLLM

- **Strengths**: PagedAttention + continuous batching = dramatically higher throughput under concurrent load; great for production APIs; supports tensor parallelism across GPUs; AWQ, GPTQ, and (more recently) gguf support.
- **Weaknesses**: GPU-resident — no meaningful CPU fallback; higher ops cost; opinionated about formats (gguf is a relative newcomer); slightly fiddly first-run (CUDA versions, PyTorch versions).
- **Format**: safetensors (HF format) is the primary path; AWQ/GPTQ for quantized; gguf is possible but not its sweet spot.
- **API**: OpenAI-compatible (`/v1/chat/completions`, `/v1/completions`).
- **Key config knobs** (all big deals):
  - `--gpu-memory-utilization 0.9` — how much of VRAM to grab. Default too low; 0.9 is often right.
  - `--max-model-len` — cap the context length you'll accept. Don't let it default to the model's full native context if you can't afford the KV cache.
  - `--tensor-parallel-size N` — split across N GPUs. Requires 2/4/8 GPUs; doesn't help a single-GPU setup.
  - `--quantization awq|gptq|fp8|...` — match your model file.
  - `--enable-prefix-caching` — if many requests share a long system prompt.
- **When it's wrong**: single-user desktop, CPU-only, constantly swapping models (vLLM wants to keep one resident).

## llama.cpp (and its `server` mode)

- **Strengths**: pure C++, runs on everything (CPU, Metal, CUDA, ROCm, Vulkan), partial GPU offload via `-ngl N` (send N layers to GPU, rest on CPU), excellent quantization ecosystem (all the Q*_K_M variants live here).
- **Weaknesses**: no continuous batching as strong as vLLM; server is basic; throughput under concurrent load is worse than vLLM.
- **Format**: gguf only (this is where gguf was invented).
- **API**: `server` exposes an OpenAI-compatible endpoint.
- **When it's right**: constrained hardware, hybrid CPU-GPU inference, want maximum control over quantization.
- **When it's wrong**: need high-concurrency API serving.

## TGI (text-generation-inference, HuggingFace)

- **Strengths**: production-grade, tensor parallel, continuous batching, used in production at HF and elsewhere; Rust + Python.
- **Weaknesses**: more complex setup than vLLM for a comparable outcome; license changed (Apache 2 pre-1.0 → custom after); some users now prefer vLLM.
- **Format**: safetensors, AWQ, GPTQ, bitsandbytes.
- **When it's right**: already on HF ecosystem, want their tooling.
- **When it's wrong**: vLLM fits your workload (usually does).

## SGLang

- **Strengths**: purpose-built for structured + agentic workloads — constrained decoding (JSON schema, regex), tool use, KV cache reuse for branching generations. Often higher throughput than vLLM for structured output.
- **Weaknesses**: smaller ecosystem; less documentation; faster-moving API.
- **When it's right**: the workload is heavy on JSON output, tool calling, branching generations.
- **When it's wrong**: plain chat serving — vLLM is simpler.

## LM Studio

- **Strengths**: GUI + local model catalog; good for non-developers and eval sessions.
- **Weaknesses**: not a production server; single-user oriented.
- **When it's right**: desktop, exploratory, trying many models quickly.

## Concurrency notes

**Continuous batching** is the difference between "one request at a time in series" and "many requests interleaved per decoding step." It's the single biggest throughput multiplier for serving workloads.

- Ollama: no continuous batching. Requests queue.
- vLLM: continuous batching + PagedAttention. Gold standard.
- TGI: continuous batching.
- llama.cpp server: parallel slots, but not continuous batching in the vLLM sense. Better than serial, worse than vLLM under load.

If your workload has more than 2-3 simultaneous users, continuous batching matters a lot. If it doesn't, it's irrelevant and Ollama is easier.

## OpenAI-compatibility

All four (Ollama, vLLM, TGI, llama.cpp server) expose OpenAI-compatible endpoints now. This is a big deal — client code is portable across runtimes. Pick the runtime based on workload; switch later if the workload changes. Don't couple your client to a runtime-specific API.

## Decision matrix (one more time, compact)

```
                          GPU-only  CPU-ok   High-throughput  Easy-setup  Format
Ollama                      ✔         ✔          ✘              ✔          gguf
vLLM                        ✔         ✘          ✔              ◐          safetensors, awq, gptq
llama.cpp server            ✔         ✔          ◐              ◐          gguf
TGI                         ✔         ✘          ✔              ◐          safetensors, awq, gptq
SGLang                      ✔         ✘          ✔ (structured) ◐          safetensors, gguf
LM Studio                   ✔         ✔          ✘              ✔          gguf
```

`✔` = yes, `✘` = no, `◐` = partial / with caveats.
