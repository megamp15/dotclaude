# Model formats and quantization

Two orthogonal choices: **file format** (how weights are packaged) and
**quantization** (precision of the weights). Get both wrong and nothing
works; get either half-wrong and everything is mysteriously slow or
dumb.

## File formats

### `safetensors`

- HuggingFace's default. Memory-mapped, safe (no arbitrary code execution on load), fast to load.
- FP16 / BF16 by default; can also hold quantized weights (AWQ, GPTQ store in safetensors shards).
- **Use with**: vLLM, TGI, Transformers, most things.
- **Don't confuse with**: the `.bin` / `.pt` / `.pth` formats — those are pickle-based. Pickle can execute arbitrary code on load. Prefer safetensors.

### `gguf`

- From the llama.cpp world. Single-file, mmap-friendly, self-describing, supports many quantization schemes.
- **Use with**: Ollama, llama.cpp, LM Studio. vLLM supports gguf but it's not the native path.
- **Filename clues**: `Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf` — the suffix tells you the quant (see below).

### `pickle` / `.bin` / `.pt` / `.pth`

- PyTorch's older format. Arbitrary code can be embedded. **Avoid for untrusted models.**
- Still common in HF repos that haven't converted to safetensors.
- Runtime loaders convert on the fly, but the download is still the risk.

### AWQ, GPTQ, EXL2, FP8, bitsandbytes

These aren't file formats as much as quantization methods with their
own packaging:

- **AWQ** (Activation-aware Weight Quantization) — int4 weights, FP16 activations; good quality/speed; vLLM and TGI support.
- **GPTQ** — older int4 method; still supported everywhere; slight quality edge in some cases, usually beat by AWQ now.
- **EXL2** — ExLlamaV2's format; flexible bit rate (2-8 bpw in fractional steps); used heavily in the local-chat community.
- **FP8** — H100/H200/Blackwell-class hardware can run FP8 natively; near-FP16 quality with ~half memory.
- **bitsandbytes** (bnb) — on-the-fly quantization (int8, int4/nf4). Used in training + inference from Transformers. Slower than dedicated formats for pure inference; common for QLoRA.

## Quantization ladder

Weights stored at lower precision = smaller file + less VRAM + faster load + **worse outputs**. The "worse" part is non-linear and depends on the task.

| Precision | Approx size (7B model) | Quality | When to use |
|---|---|---|---|
| FP16 / BF16 | ~14 GB | Full | When VRAM is plentiful and quality is paramount |
| Q8_0 | ~7.5 GB | Near-perfect; hard to distinguish from FP16 for most tasks | Default for "I want max quality on quant" |
| Q6_K | ~5.5 GB | Very good; tiny drop | Good compromise |
| Q5_K_M | ~4.8 GB | Good; slight drop on edge cases | Strong default for chat |
| **Q4_K_M** | **~4.1 GB** | **Noticeable but usable drop** | **Most common default** — good quality/size tradeoff |
| Q4_K_S | ~3.9 GB | Slightly worse than Q4_K_M; small size win | When size pressure is real |
| Q3_K_M | ~3.2 GB | Real quality drop; reasoning + code degrade | Only when Q4 won't fit |
| Q2_K | ~2.6 GB | Substantial degradation; outputs get weird | Rarely worth it; prefer smaller model at higher quant |

**Rule of thumb**: a smaller model at Q5 usually beats a larger model at Q2. Don't quantize a 70B to Q2 to make it fit — run a 13B at Q5_K_M instead.

**Task sensitivity to quantization**:

- **Chat / creative writing**: tolerates Q4_K_M fine.
- **Code generation**: sensitive around Q4; prefer Q5_K_M or higher if possible.
- **Math / reasoning**: degrades faster; Q6 or Q8 is safer.
- **Tool use / structured output**: format adherence drops noticeably below Q5.
- **Long-context retrieval**: weights quantization matters less than KV cache quantization (next section).

## KV cache quantization (separate axis)

Often overlooked. The KV cache can be larger than the model weights at
long context. Some runtimes support quantizing the KV cache too
(FP8 or int8) — cuts KV cache memory ~in half. Quality impact is small
for most tasks but can be noticeable at very long context.

- vLLM: `--kv-cache-dtype fp8` (Hopper/Blackwell) or `fp8_e4m3` / `fp8_e5m2`.
- llama.cpp: `--cache-type-k q8_0 --cache-type-v q8_0`.

If you're VRAM-constrained on long-context workloads, try this before dropping the weights' quant level further.

## AWQ vs GPTQ vs gguf for quantized serving

| Format | Best for | Tooling |
|---|---|---|
| **AWQ** | High-throughput GPU serving | vLLM, TGI |
| **GPTQ** | Same niche as AWQ, slightly older | vLLM, TGI, AutoGPTQ |
| **gguf** | Flexible deployment, CPU+GPU, desktop | Ollama, llama.cpp |
| **FP8** | Newest GPUs (H100+), near-FP16 quality | vLLM, TGI |
| **EXL2** | Community-driven, fractional bit rates | ExLlamaV2, some GUI frontends |

If you're using vLLM and want quantized → AWQ first, FP8 on H100+. If you're using Ollama or llama.cpp → gguf is your only real option. If you're on CPU → gguf (Q4_K_M or Q5_K_M).

## Verifying you got what you think

After downloading a model, check:

1. **File size matches quant level** — Q4 of a 7B should be ~4 GB, not ~14 GB. If it's 14 GB, the "Q4" in the filename lied or it's really FP16 mislabeled.
2. **Runtime loads without warnings** — vLLM / llama.cpp will warn on format mismatch; don't ignore.
3. **Smoke test the output** — one prompt, known-good. If the model replies with garbage, the quant is broken (corrupted download, wrong revision, unsupported quant method for your runtime build).
4. **Chat template matches** — many failures are actually template mismatches: the model was trained on ChatML, you're feeding it Llama 3 format, and it responds confusingly. Check the tokenizer config.

## Supply-chain reminder

- Prefer `safetensors` over pickle-based formats.
- Prefer official / first-party uploads (Meta, Mistral, Google, Qwen, Alibaba) over random reuploads.
- Watch for misnamed quants — a file called `Q4_K_M.gguf` can be anything; trust the publisher.
- For production, pin the exact HF commit hash (`--revision <sha>`), not just `main`.
