---
source: stacks/vllm-ollama
name: inference-ops
description: Day-2 operations for self-hosted LLM inference — monitoring, capacity, upgrades, fallbacks, client integration patterns. Load when operating a running vLLM or Ollama deployment.
triggers: vllm serve, ollama serve, inference monitoring, llm metrics, llm autoscaling, ollama systemd, vllm docker, llm upgrade, llm cold start
globs: ["**/docker-compose*.yml", "**/*.service", "**/systemd/**/*.conf", "**/k8s/**/*.yaml", "**/helm/**/*.yaml"]
---

# Inference ops

Operational rules for a running LLM inference service. Assumes the
choice of runtime is already made (see `core/skills/llm-serving`).

## Health and liveness

### Ollama

- `/api/tags` returns 200 with the model list — safe liveness probe.
- `/api/show` with a specific model tells you if a model is loaded, but it's expensive.
- No distinct readiness semantics; "is the process up" is what you get.

### vLLM

- `/health` — lightweight, returns 200 when the engine is accepting requests.
- `/v1/models` — returns configured models. Also lightweight.
- `/metrics` — Prometheus-format; exposes engine internals. Not for liveness; scrape on interval.

## Autoscaling — the caveats

LLM inference pods have a long warm-up:

- Ollama: tens of seconds to load a model from disk to VRAM.
- vLLM: same, plus the first-request compile/capture if `torch.compile` is on.
- Model download on first pod start: minutes.

Implications:

- **Default HPA settings are wrong.** Scale-up reactivity should match your SLO vs. cold-start tradeoff.
- **Keep a hot minimum.** Don't let `minReplicas: 0` take the service from zero.
- **Scale-down slowly.** Coasting to zero fast and then cold-starting spikes is a recipe for slow tail latency.
- **Prewarm newly-scheduled pods**: init container or startup probe that makes a single dummy request before marking ready.

Metrics to drive autoscaling (vLLM):

- `vllm:requests_waiting` — queue depth. Scale when waiting > threshold for N minutes.
- `vllm:gpu_cache_usage_perc` — KV cache saturation. Scale when > 80% for N minutes.
- `vllm:time_per_output_token_seconds` — latency. Scale when P95 > SLO for N minutes.

Don't scale on `requests_running` alone; it saturates at concurrency limit and becomes flat.

## Client-side patterns

### Retries

Use a retry library (e.g., `tenacity`) with exponential backoff. Retry on:

- `5xx` responses.
- Connection errors.
- **Not** on 4xx — those are client errors; retrying won't help.
- **Not** on 429 without respecting `Retry-After`.

Budget retries: **3 retries over ~10s** for interactive, more for batch.

### Timeouts

The client must set a timeout. The runtime will happily generate for minutes if the client doesn't cut it off.

- **HTTP client-side timeout** on the whole request: generous (e.g., 5-10 min for long generations) but set.
- **`max_tokens`** on the request — always. Without it, the model generates until EOS or its own context limit.
- **`timeout`** param in the OpenAI SDK — set it.

### Streaming

For interactive UX, always stream. Both Ollama and vLLM support SSE streaming via the OpenAI API. Don't buffer the entire response server-side; show tokens as they arrive.

### Circuit breaker / fallback

When the LLM is unhealthy (too-slow responses, 5xx storm), degrade gracefully:

- Cached / canned responses for common prompts.
- Fallback to a smaller model (Ollama can host multiple).
- Fallback to a hosted API (OpenAI, Anthropic) as a last resort — document cost implications.

Without a fallback, LLM-dependent features become "completely broken" instead of "degraded."

## Monitoring dashboard — the first set of panels

- **Request rate** (requests/sec) per model.
- **P50 / P95 / P99 TTFT** (time-to-first-token).
- **P50 / P95 / P99 total generation time**.
- **Tokens generated / second** (throughput).
- **Queue depth** (`vllm:requests_waiting`).
- **GPU utilization + memory** (from `nvidia-smi` exporter).
- **KV cache utilization** (`vllm:gpu_cache_usage_perc`).
- **Error rate** by status code.
- **Upstream cost / token** if you have a hybrid with hosted APIs.

Alerts on:

- TTFT P95 > SLO for N minutes.
- Error rate > X% for N minutes.
- Queue depth > M for N minutes.
- GPU memory usage > 95% for N minutes.

## Upgrades

### vLLM

- Pin version in your Dockerfile / requirements. `vllm==0.6.4`, not `vllm`.
- **Read the release notes.** Minor versions change flags and defaults regularly.
- Upgrade in staging: start with the same model + config you run in prod. Compare:
  - Cold-start time.
  - Single-request latency.
  - Concurrent throughput at target load.
- Deploy with blue-green or canary, not in-place. Rollback path required.

### Ollama

- Package upgrades in place are usually fine; Ollama's API surface has been very stable.
- After upgrade, validate model behavior (sample prompts, known-good outputs).

### Model upgrades

- Treat a model upgrade as a deploy. Staging → canary → prod.
- Eval against a fixed prompt set; compare scores.
- Client code must handle the model's output format. Chat template changes between model generations are common — test before swapping.

## Resource limits + multi-tenancy

- **One model per pod / service** in production. Mixing models on one vLLM serve is possible but gives up isolation.
- **Memory requests/limits** don't help with GPU memory — that's managed at the runtime config level (`gpu-memory-utilization`, `OLLAMA_MAX_LOADED_MODELS`).
- **Per-client rate limits** at the proxy, not the runtime. Don't let one client saturate the queue for others.
- **Separate dev and prod GPUs.** A dev workload OOM'ing doesn't take prod down.

## Systemd unit (Ollama) — reference

`/etc/systemd/system/ollama.service.d/override.conf`:

```ini
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11434"
Environment="OLLAMA_MODELS=/var/lib/ollama/models"
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_NUM_PARALLEL=2"
Environment="OLLAMA_FLASH_ATTENTION=1"
Restart=on-failure
RestartSec=5s
```

Reload with `systemctl daemon-reload && systemctl restart ollama`. Logs: `journalctl -u ollama -f`.

## Docker Compose (vLLM) — reference

```yaml
services:
  vllm:
    image: vllm/vllm-openai:v0.6.4
    restart: unless-stopped
    ports: ["127.0.0.1:8000:8000"]
    volumes:
      - hf-cache:/root/.cache/huggingface
    environment:
      HUGGING_FACE_HUB_TOKEN: ${HF_TOKEN}
    command: >
      --model meta-llama/Llama-3.1-8B-Instruct
      --revision <pinned-sha>
      --dtype bfloat16
      --max-model-len 16384
      --gpu-memory-utilization 0.90
      --enable-chunked-prefill
      --enable-prefix-caching
      --api-key ${VLLM_API_KEY}
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 300s
volumes:
  hf-cache:
```

Notes:

- `start_period: 300s` for healthcheck — first startup includes model download on a cold cache.
- API key required.
- Ports bound to localhost; real reverse proxy in front handles public exposure.

## Do-not operational list

- Do not expose Ollama or vLLM to untrusted networks without auth + rate limits at a reverse proxy.
- Do not autoscale to zero unless you accept cold-start latency.
- Do not treat `--max-model-len` as free — every token of context caps batch × context squared in KV cache.
- Do not mix model versions on the same `/v1/chat/completions` endpoint without version-pinned client calls. Silent model changes cause silent behavior changes.
- Do not upgrade vLLM in place in prod. Always blue-green.
- Do not skip health checks. Unhealthy replicas in a load-balancer pool poison throughput.
