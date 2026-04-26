---
source: stacks/vllm-ollama
---

# Stack: vLLM / Ollama

Deployment conventions for the two most common self-hosted LLM
runtimes. Layers on `core/`. Paired with the `core/skills/llm-serving`
domain hub (read that for cross-runtime decisions — format selection,
memory sizing, runtime comparison). This stack covers operational
conventions for running these tools day-to-day.

## Which is this stack for

- You've decided on **Ollama** or **vLLM** as the runtime (see the `llm-serving` hub for the choice).
- You're writing Ansible / Docker / systemd / K8s manifests to deploy one of them.
- You need operational conventions: config, upgrades, monitoring, capacity planning.

Not for deciding *whether* to use them — that's the domain hub's job.

## Ollama

### Install + config

- **Linux**: official install script or official apt/dnf packages. Run as a systemd service under the `ollama` user.
- **macOS**: Homebrew cask or official installer.
- **Docker**: `ollama/ollama` image. Required for consistent behavior across hosts or GPU pass-through from Kubernetes.

Key config via env vars (set in `/etc/systemd/system/ollama.service.d/override.conf` or docker env):

| Var | Purpose |
|---|---|
| `OLLAMA_HOST` | Bind address. Default `127.0.0.1:11434`. Set to `0.0.0.0:11434` only if fronted by a reverse proxy with auth. |
| `OLLAMA_MODELS` | Where models live. Default `~/.ollama/models`. Point at a ZFS dataset / large disk. |
| `OLLAMA_KEEP_ALIVE` | How long a model stays resident after last request. Default 5m. Raise if you have the VRAM and frequent traffic. |
| `OLLAMA_NUM_PARALLEL` | Max concurrent requests per model. Default 1. Raise cautiously; Ollama's concurrency story is weaker than vLLM's. |
| `OLLAMA_MAX_LOADED_MODELS` | Cap models in memory at once. |
| `OLLAMA_FLASH_ATTENTION` | Enable for modest throughput bump on supported GPUs. |
| `OLLAMA_DEBUG` | Verbose logs when diagnosing issues. |

### Model management

```bash
ollama pull llama3.2:3b
ollama list
ollama show llama3.2:3b --modelfile
ollama rm llama3.2:3b
```

- **Modelfile**: Dockerfile-like syntax for customizing a model (system prompt, params, tokens, adapters). Check customized modelfiles into git.
- **Model tags** aren't immutable — `llama3.2:latest` changes over time. For reproducibility, pin by digest (`ollama show` gives it) or to a specific version tag (`llama3.2:3b-instruct-q4_K_M`).
- **Local-only**: models can be added from local gguf files via a Modelfile with `FROM /path/to/file.gguf`.

### Deployment patterns

- **Single machine (homelab/dev)**: systemd unit + `OLLAMA_HOST=127.0.0.1` + Tailscale / reverse proxy.
- **Behind reverse proxy with auth**: Nginx / Caddy / Traefik in front; basic auth or OIDC in the proxy; Ollama bound to localhost.
- **Kubernetes**: `ollama/ollama` image; GPU via NVIDIA device plugin; models on a PVC (Longhorn / NFS / Ceph) so pods don't re-download on restart.
- **Docker Compose + GPU**: `deploy.resources.reservations.devices` with `driver: nvidia`.

### Client API

OpenAI-compatible since late 2024. Point any OpenAI client at `http://host:11434/v1`:

```python
from openai import OpenAI
client = OpenAI(base_url="http://host:11434/v1", api_key="ollama")  # any string
```

Native `/api/generate` and `/api/chat` endpoints are still supported; the OpenAI path is preferred for new code.

### Ollama limits — when to upgrade to vLLM

- More than a handful of concurrent users.
- Need JSON-schema-constrained output at scale (Ollama supports JSON mode; vLLM/SGLang do richer constrained decoding).
- Want tensor parallelism across multiple GPUs.
- Need the throughput headroom continuous batching gives.

## vLLM

### Install + config

- **Python pip install** into a venv: `uv pip install vllm`. Ensure CUDA / PyTorch versions match.
- **Docker**: `vllm/vllm-openai` image. Recommended for production — saves the CUDA/Python dependency dance.
- **Run** as an OpenAI-compatible server:
  ```bash
  vllm serve meta-llama/Llama-3.1-8B-Instruct \
      --host 0.0.0.0 --port 8000 \
      --gpu-memory-utilization 0.9 \
      --max-model-len 16384 \
      --tensor-parallel-size 1 \
      --served-model-name my-llm
  ```

### Key flags

| Flag | Meaning | Typical value |
|---|---|---|
| `--gpu-memory-utilization` | Fraction of VRAM vLLM takes | `0.90` (default 0.90 recent; older versions 0.9 too) |
| `--max-model-len` | Max context tokens accepted | Set to the real ceiling you serve — don't let it default to native |
| `--tensor-parallel-size` | Split model across N GPUs | 1 (default); 2/4/8 for models too big for one GPU |
| `--quantization` | `awq` / `gptq` / `fp8` — must match your weights | — |
| `--dtype` | `auto` / `bfloat16` / `float16` | `auto` usually; `bfloat16` on Ampere+ |
| `--max-num-seqs` | Concurrent request cap | 256 default; tune down if KV cache is tight |
| `--enable-prefix-caching` | Dedupe shared prompt prefixes | On, if many requests share a system prompt |
| `--kv-cache-dtype` | `auto` / `fp8_e5m2` — halve KV cache | `fp8_e5m2` on Hopper/Blackwell to pack more context |
| `--served-model-name` | What client sees as the model name | Short, stable ID (`llama-3.1-8b`) |
| `--api-key` | Required bearer token for clients | Real value from a secret, not baked in |
| `--enable-chunked-prefill` | Interleave prefill + decode | On in recent versions; smooths latency under load |

### Deployment patterns

- **Docker**: `vllm/vllm-openai` image, `--gpus all`, volume-mount HF cache (`~/.cache/huggingface`) so model downloads persist.
- **Kubernetes**: Deployment with 1 replica per GPU (or DP via replicas if model fits; TP via a single pod with multiple GPUs for bigger models). Liveness/readiness on `/health`. Resource limit `nvidia.com/gpu: N`.
- **systemd** on bare metal works; simpler than K8s for small deploys.

### Model selection

vLLM expects HuggingFace format (safetensors + `config.json` + tokenizer files) or known quantized variants (AWQ, GPTQ, FP8). gguf support exists but isn't the primary path.

- Pin model by HF revision: `--revision <sha>` — guards against silent updates.
- Pre-download to a shared volume for multi-node setups; avoid each pod downloading 40 GB.
- Pre-download for first-boot speed. HF cache default `~/.cache/huggingface/hub`.

### Client API — OpenAI compatible

```python
from openai import OpenAI
client = OpenAI(base_url="http://vllm-host:8000/v1", api_key="your-key")

resp = client.chat.completions.create(
    model="my-llm",
    messages=[{"role": "user", "content": "Hello"}],
    temperature=0.7,
    max_tokens=512,
)
```

Streaming, tool calling, JSON schema (`response_format={"type": "json_schema", "json_schema": {...}}`), guided regex — all supported.

### Monitoring + scaling

- **`/metrics`** endpoint: Prometheus-format. Scrape with a ServiceMonitor (K8s) or a plain scrape config.
- Key metrics: `vllm:requests_running`, `vllm:requests_waiting`, `vllm:time_to_first_token_seconds`, `vllm:time_per_output_token_seconds`, `vllm:num_tokens_total`.
- **HPA** on `vllm:requests_waiting` for autoscaling if your cluster supports metrics-based autoscaling. Caveat: replicas of a vLLM pod each need GPU + time to warm; scale-out is not instant.

### Upgrade discipline

- Pin version (`vllm==0.6.4` or Docker tag). Don't chase `latest` — vLLM is fast-moving; breaking changes are normal between minor versions.
- Test model load + a sample request in staging before pushing to prod.
- `--enable-lora` and other newer features often land in specific versions; read release notes before upgrading.

### Capacity planning (for operational docs)

Reference the `core/skills/llm-serving` domain hub, specifically `memory-and-batching.md`. The sizing formulas live there — this stack assumes you've done that work and is about *operating* the thing.

## Shared: reverse proxy conventions

Putting Ollama or vLLM behind a real reverse proxy is almost always
the right call. Conventions:

- **TLS terminates at the proxy**; Ollama/vLLM listens on localhost or cluster-internal.
- **Authentication** at the proxy: bearer token, OIDC, basic auth (behind TLS), or a service-mesh-level identity.
- **Rate limiting** at the proxy — the runtime itself doesn't rate-limit per-client.
- **Logging** at the proxy for audit + billing; runtime logs are operational, not access.
- **Health checks** on `/health` (vLLM) or `/api/tags` (Ollama; returns 200 with model list).

## Do not

- Do not run these open to the internet without auth. The OpenAI-compat API will happily serve anyone who finds it.
- Do not use `latest` tags — both Ollama model tags and vLLM container tags. Pin.
- Do not share GPUs between Ollama and vLLM on the same host. They'll fight over VRAM; it won't go well.
- Do not run vLLM with `--max-model-len` at the model's native maximum "because it supports it" — pay for the KV cache only up to the context length you actually serve.
- Do not skip the `gpu-memory-utilization` check on vLLM — default leaves headroom; if you lowered it for headroom, that's fine; if you raised it, watch for OOM under load.
- Do not forget `--api-key` / auth on vLLM exposed outside localhost.
- Do not deploy these to autoscaling without a warm-up strategy. Cold starts are minutes, not seconds.
