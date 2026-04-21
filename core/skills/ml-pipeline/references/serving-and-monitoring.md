# Serving and monitoring

## Batch vs. online

| Pattern | When | Throughput | Latency |
|---|---|---|---|
| **Batch** | Offline / scheduled | High | Minutes–hours |
| **Near-real-time** | Every N minutes | High | Minutes |
| **Online** | Per request | Moderate | ms–seconds |
| **Streaming** | Per event | High | Low latency, stateful |

Choosing:

- Daily churn predictions → batch.
- Fraud score on checkout → online.
- Feature updates from events → streaming.

## Online serving options

### HTTP servers (OSS)

- **BentoML** — Pythonic, swappable runners, great for sklearn /
  PyTorch / TF; builds Docker + OCI artifacts.
- **Triton Inference Server** (NVIDIA) — multi-framework, GPU-
  optimized, dynamic batching, ensemble models. Heavy config.
- **Ray Serve** — Python-native, horizontal scaling, composition.
- **TorchServe** — PyTorch-specific, simpler than Triton.
- **KServe** — K8s-native CRD, supports many backends (PyTorch,
  TF, sklearn, XGBoost, custom); autoscaling to zero.
- **FastAPI + model.load** — fine for low-scale custom services.

### Managed

- **SageMaker Endpoints** — real-time / serverless / async.
- **Vertex AI Endpoints** — GCP counterpart.
- **Azure ML Endpoints** — similar.
- **Databricks Serving** — integrated with Unity Catalog.
- **Modal / Anyscale** — PaaS for ML serving.

Default: **BentoML on K8s / Cloud Run** for small/medium scale;
**Triton + KServe** for multi-model GPU serving.

## Inference patterns

### Single prediction

Simple, cleanest. Most real-time systems.

### Dynamic batching

Server groups incoming requests into a batch before model call.
Massive throughput gains on GPU.

- Triton has best-in-class dynamic batching.
- Configure max wait (e.g., 5ms) and max batch size.

### Ensemble / pipeline

Multiple models chained: preprocessor → model A → postprocessor →
model B → aggregate. Triton and Ray Serve express these natively;
manual wiring in simpler frameworks.

### Async inference

- Client submits job; gets ID; polls or receives webhook.
- Good for heavy tasks (long-running transformers, LLMs).
- SageMaker Async Inference, Ray's async APIs.

## Scaling

- **Horizontal** — more replicas. Stateless inference scales
  linearly to the limit of shared resources (feature store, DB).
- **Vertical** — bigger machine / GPU. Required for large models.
- **Autoscaling triggers**:
  - CPU / GPU utilization.
  - QPS / queue depth (KEDA).
  - Custom business metric.
- **Cold start** — pre-warm replicas; scale-to-zero kills latency
  for first-request users.

## Canary / shadow deployments

- **Shadow** — new model receives copy of prod traffic, results
  logged but not served. Zero user risk; compare predictions.
- **Canary** — 5% of traffic to new; monitor; ramp.
- **A/B** — 50/50 split tied to an experiment.

KServe, Istio, Flagger, Linkerd Canary support weight-based
routing.

## Feature serving

### Online feature store

- **Redis** — fast, simple.
- **DynamoDB** — serverless, scales.
- **Feast Online Store** — Redis, DynamoDB, Postgres backends.
- **Tecton / Vertex / Databricks** — managed online features.

Response contract:

- Single request fetches all features for a given entity ID.
- < 10ms p99.

### Point-in-time correctness (training)

Offline feature store joins features to labels using the event
timestamp, guaranteeing no future leakage.

### Skew monitoring

Log serving features → compare distributions against training-time
features.

## Drift detection

Four drift types, different responses:

### Covariate (feature) drift

Distribution of X changes; P(X) shifts. Model trained on stale X.

Detection:

- **Population Stability Index (PSI)** — simple, bucketed,
  interpretable. PSI > 0.2 → notable shift.
- **KS test / Wasserstein distance** — continuous features.
- **JS divergence** — categorical.

Response: usually retrain.

### Label drift

Distribution of Y changes. E.g., seasonality, product mix.

Detection: monitor target rates over time.

Response: retrain on recent labels; possibly reweight training.

### Concept drift

P(Y|X) changes — the relationship between inputs and outputs
shifts. Usually the hardest.

Detection: monitor online performance (if labels available) and
predictions vs. actuals.

Response: retrain; investigate if the relationship is truly
changing or the model is wrong.

### Prediction drift

Output distribution shifts, independent of inputs. Indicates
something is wrong: data pipeline broken, feature missing, etc.

Detection: monitor prediction histograms over time.

Response: investigate. Often a data bug, not a model issue.

### Tools

- **Evidently AI** — OSS; great reports; Prometheus export.
- **WhyLabs** — managed.
- **Arize / Fiddler** — commercial observability for ML.
- **NannyML** — estimates accuracy without labels (performance
  estimation).
- Custom Prometheus exporters + PromQL on histograms.

## Quality monitoring (with labels)

When labels arrive (delayed / batch):

- Compute rolling accuracy / AUC / F1 over last N days.
- Alert on drops beyond SLO.
- Slice-level monitoring (per segment).

Time-to-label is often long (days–weeks). Use proxy metrics in
the interim.

## Latency SLOs

Example:

- p50 < 50ms, p95 < 200ms, p99 < 500ms for online inference.
- p95 training pipeline end-to-end < 6h.
- Batch inference: 100M predictions in 30 min.

Budget per stage:

- Feature fetch: 5–15 ms.
- Preprocessing: 1–5 ms.
- Model: 20–150 ms.
- Postprocess + response: 1–10 ms.

Beyond that range: look at dynamic batching, GPU, model
distillation, caching, model pruning/quantization.

## Cost monitoring

- **Per-endpoint spend**: tag + dashboard.
- **Per-prediction cost**: compute / requests — sanity-check vs.
  business value.
- **Underutilized GPUs**: biggest cost sink; consolidate.
- **Spot / preemptible** for batch: ~70% savings with checkpoint
  support.

## Observability stack for ML

Per-request logs:

- Request ID, model version, features (or hash), prediction,
  latency.
- Don't log PII in features; hash or redact.

Metrics:

- QPS, error rate, latency percentiles (per endpoint).
- Model version.
- Prediction distribution.
- Feature availability (% non-null).
- Drift scores (PSI, KS) as gauges.

Traces:

- Span per stage: feature fetch, preprocess, inference,
  postprocess. OTel propagation so you can tie a prediction back
  to the upstream request.

Alerts:

- Latency SLO breach.
- Error rate spike.
- PSI > threshold.
- Prediction distribution anomaly.
- Feature missing rate > threshold.

## Rollback discipline

If a new model deploys and metrics degrade:

1. **Auto-rollback** on SLO breach — do this.
2. Keep the old model version warm for N hours.
3. Prefer rollback over "hotfix in production".
4. Post-mortem — what was missed in offline eval / canary that
   surfaced in full rollout?

## Multi-model hosting

For many small models (dozens–thousands):

- **Triton Multi-Model** — load on demand.
- **BentoML Monitor / Multi-Runner**.
- **Managed** (SageMaker Multi-Model Endpoints).

Saves GPU cost dramatically. Constraint: similar framework /
backend.

## When to call it AI

Rule: if the model is < 5% better than rules / a heuristic / a
stats model, don't ship the ML pipeline. The operational burden
won't be recouped.
