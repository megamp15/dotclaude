# Memory sizing, KV cache, batching, multi-GPU

The "will this fit?" question, answered honestly.

## The three things that eat VRAM

1. **Weights** — fixed per model + quant. Biggest chunk at short context.
2. **KV cache** — scales with `seq_len × batch_size × n_layers × 2 × n_kv_heads × head_dim × dtype_bytes`. At long context + high batch, this dwarfs the weights.
3. **Activations / overhead** — 10-15% overhead for the runtime, optimizer state (none at inference), CUDA workspace, etc.

Total ≈ `weights_GB + kv_cache_GB + (weights_GB × 0.12)`.

Plan for the worst-case combination: full context + full batch.

## Weight sizing (quick table)

| Params | FP16/BF16 | Q8_0 | Q5_K_M | Q4_K_M | Q3_K_M |
|---|---|---|---|---|---|
| 7B | ~14 GB | ~7.5 | ~4.8 | ~4.1 | ~3.3 |
| 8B | ~16 GB | ~8.5 | ~5.6 | ~4.7 | ~3.7 |
| 13B | ~26 GB | ~14 | ~9 | ~7.5 | ~6.0 |
| 34B | ~68 GB | ~36 | ~24 | ~20 | ~16 |
| 70B | ~140 GB | ~75 | ~50 | ~42 | ~34 |

Add ~10% to these for CUDA/runtime overhead. That's the "weights fit" check.

## KV cache sizing

Per-token, per-request (approximate, for Llama-style GQA):

```
kv_per_token_bytes = 2 * n_layers * n_kv_heads * head_dim * dtype_bytes
```

Example: Llama 3.1 8B Instruct (n_layers=32, n_kv_heads=8, head_dim=128, FP16):

```
kv_per_token = 2 * 32 * 8 * 128 * 2 = 131,072 bytes ≈ 128 KB/token
```

For 32k context, 8 concurrent requests:

```
kv_cache = 32,768 * 8 * 128 KB = 32 GB
```

That's bigger than the FP16 weights (~16 GB). Welcome to serving at long context.

**Levers to reduce KV cache:**

- Lower `max_model_len` / context cap.
- Fewer concurrent requests (`--max-num-seqs`).
- Enable **prefix caching** for shared system prompts — vLLM dedupes the shared prefix.
- Quantize KV cache to FP8 or int8 (≈ halves it).
- Use a model with **grouped-query attention (GQA)** or **multi-query attention (MQA)** — `n_kv_heads << n_heads`. Most modern models already do this.

## Sizing checklist (before you download)

Answer all five:

1. Model params × quant dtype → **weight_bytes**. (Use the table above or the actual file size once known.)
2. Max context you'll accept × max concurrent requests × per-token KV cost → **kv_cache_bytes_worst_case**.
3. Overhead = `weight_bytes × 0.12`.
4. Total = weight + kv_cache_worst_case + overhead.
5. Compare to your VRAM. Leave at least 1-2 GB headroom. Don't go over 90% utilization.

If Total > VRAM:

- Lower context cap first (biggest lever usually).
- Then lower concurrency.
- Then drop KV cache to FP8.
- Then drop model quant (Q5 → Q4).
- Then switch to a smaller model.

## Batching modes

### Static batching (old-school)

All requests in a batch must finish before the next starts. Terrible for chat — one long generation holds up short ones. **Avoid.**

### Dynamic batching

Pad batch at each step; longer-running generations pad shorter ones. Better, but wasted compute on padding.

### Continuous batching (vLLM, TGI, SGLang)

Each decoding step runs a fresh batch of currently-active requests. New requests join mid-stream; finished requests drop out. No padding waste. **This is the big one.**

PagedAttention (vLLM's innovation) complements this — KV cache allocated in small blocks instead of contiguous arenas; fragmentation solved.

Under continuous batching, **effective throughput scales with GPU utilization**, not with request-serial execution. 4-8× throughput gains over serial are common.

## Multi-GPU strategies

### Tensor parallelism (TP)

Split each layer's tensors across GPUs. All GPUs work on every token.

- **When**: single model too big for one GPU, OR you want lower latency on a big model.
- **Config**: vLLM `--tensor-parallel-size N`. N must divide key model dims (usually 2, 4, 8).
- **Catches**: NVLink / high-speed interconnect really helps; PCIe-only is a perf hit.

### Pipeline parallelism (PP)

Split layers across GPUs; each GPU handles a consecutive slab of layers. Tokens flow through.

- **When**: model too big even for TP across all your GPUs.
- **Downsides**: latency hit from pipeline bubbles; hard to do well.
- Usually combined with TP (e.g., TP=4, PP=2 on 8 GPUs) for very large models.

### Data parallelism (DP)

Replicate the full model on each GPU; load-balance requests across replicas.

- **When**: model fits on one GPU, you want throughput, and you have multiple GPUs.
- **How**: run N copies of your vLLM server, put them behind a load balancer.
- **vs TP**: DP is simpler and better when the model fits. TP is for models that don't fit.

### Rule

- Model fits on one GPU → DP (one vLLM per GPU + LB). Simpler, more throughput.
- Model doesn't fit on one GPU → TP across the minimum GPUs needed.
- Model doesn't fit across all GPUs → TP + PP, or smaller model, or more GPUs.

## Throughput levers (cheat sheet)

If throughput disappoints, try in order:

1. `--gpu-memory-utilization 0.9` (vLLM) — reclaim headroom.
2. Raise `--max-num-seqs` — allow more concurrent requests.
3. Lower `--max-model-len` to the real max you serve — frees KV cache.
4. Enable prefix caching — if many requests share long system prompts.
5. Try FP8 KV cache (`--kv-cache-dtype fp8_e5m2`) on Hopper/Blackwell.
6. Check: are your clients actually sending requests concurrently, or waiting on each other? Many "low throughput" issues are sequential clients.
7. Check: is tokenization on client side? Server-side? Benchmark end-to-end, not just model inference.

## Latency levers

Different optimization from throughput:

- **Prefix caching** — cuts TTFT (time to first token) when prompts share a prefix.
- **Speculative decoding** — small draft model proposes tokens; big model verifies. vLLM supports it. Can 2-3× decode speed on the right workload.
- **Chunked prefill** — interleave prefill and decode instead of blocking. Helps when one user's big-context prefill would starve others' decodes.
- **Smaller model + higher quant quality** — a 7B at Q8 may be faster *and* better than a 34B at Q3 on the same hardware.

## Debug prompts when OOM

When a user reports OOM, ask:

1. Which runtime, which version? (vLLM 0.6 vs 0.7 changed defaults; Ollama vs llama.cpp vs …)
2. Full command / config?
3. `nvidia-smi` output at failure?
4. When does it fail — startup or after N tokens?
5. Batch size / concurrency?
6. Context length being requested?

Don't guess; ask. OOM is reproducibly diagnosable with the right facts.
