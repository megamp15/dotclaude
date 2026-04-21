# Pipeline stages

## Ingest and validate

Every pipeline starts with data landing in a known place with a
known shape. Non-negotiables:

- **Schema**: typed (parquet, delta, Avro, proto) over CSV/JSON.
- **Validation at ingest**: Great Expectations, Pandera, Deequ,
  Soda. Run on every batch; fail loudly.
- **Partitioning** by date (always) and by high-cardinality
  dimension if you read that way.
- **Idempotency**: re-running on the same source should yield the
  same sink.
- **Backfill plan**: can you re-ingest yesterday without
  corrupting today?

### Common sinks

- **Data warehouse** (BigQuery, Snowflake, Redshift) for analytical.
- **Lakehouse** (Delta Lake, Iceberg, Hudi) — open format, cheap,
  queryable.
- **Feature-specific stores** for serving (Redis, DynamoDB, online
  feature store).

## Feature engineering

Options, increasing complexity:

1. **Inline in training / inference code.** Fine for 1 model. No
   sharing. Risk of skew.
2. **Feature library** — reusable functions. Better; still no
   runtime store.
3. **Feature store** — offline store (for training) + online store
   (for inference), same definition. Feast is the OSS reference;
   Tecton and Databricks FS are managed.

### When a feature store pays off

- **Multiple models share features** — computing twice wastes
  compute and risks drift.
- **Batch-trained, online-served** — offline/online parity is the
  whole point.
- **Point-in-time correctness** — "what did this feature look like
  at time T?" matters for training.

### When it doesn't

- Single model, single team, simple features → overkill.
- Features derived at inference from request payload only → no
  store needed.

### Point-in-time correctness

A training row labeled at `t=2024-01-01` must use features
computed **before** `t` — never after. Feature stores enforce this
via event-time joins. Rolling your own requires care; Feast /
Tecton get it right.

## Training orchestration

### Local → distributed

- **Local** — laptop, notebook; fine for exploration.
- **Single VM / GPU** — Docker or a managed notebook (SageMaker,
  Vertex Workbench, Databricks).
- **Distributed (data parallel)** — Horovod, PyTorch DDP,
  DeepSpeed. Scale data across GPUs, same model.
- **Distributed (model parallel)** — required when model doesn't
  fit. FSDP (PyTorch), DeepSpeed ZeRO, Megatron. Rare outside LLMs.
- **Managed** — Ray Train, SageMaker Training Jobs, Vertex
  Training, Kubeflow Training Operator.

### Orchestration

- **Airflow** — mature, ubiquitous, opinionated DAGs.
  Batch-centric; ML features are grafted on.
- **Dagster** — software-defined assets; better semantics for ML;
  newer.
- **Prefect** — flow-oriented; good DX.
- **Kubeflow Pipelines** — K8s-native; verbose YAML/Python.
- **Metaflow** — Netflix OSS; Python-first; `@step` decorators;
  pairs with AWS nicely.
- **Flyte** — Python-native, typed, K8s-native.

Pick one. Don't mix unless forced.

### Training discipline

- **Every run is tracked.** Hyperparameters, data version, code
  commit, metrics, model artifact. MLflow / W&B.
- **Set the random seed** — and log it.
- **Train on a fixed data snapshot** — not "whatever's in the
  warehouse right now". Freeze via DVC / Delta time travel.
- **Eval is separate from training loop** — runs on a gold set;
  gates the registry push.

## Evaluation

Layer your evals:

1. **Unit tests on data transforms** — does the feature compute
   correctly? Same input → same output.
2. **Smoke train** — tiny dataset, 1 epoch; confirms code runs.
3. **Offline eval** — proper held-out set. Metrics depend on the
   task (AUC, F1, RMSE, MAP, ...).
4. **Slice metrics** — evaluate per segment (region, customer tier,
   demographic). Catches fairness / bias issues + hidden regressions.
5. **Business metric** — proxy for what matters (lift, conversion,
   revenue); often only observable post-deployment via A/B test.

### Regression gates

CI runs offline eval on every PR that touches model or data
pipeline. Block if:

- Top-line metric drops > X%.
- Any slice metric drops > Y%.
- Latency increases > Z%.

Thresholds defined in `eval/gates.yaml`.

## Model registry

- **MLflow Model Registry** — OSS, works anywhere MLflow works.
- **SageMaker Model Registry** — AWS-native; cross-account ok.
- **Vertex Model Registry** — GCP-native.
- **W&B Models** — hosted, strong UI.

Registry stores:

- Model artifact.
- Version.
- Stage (None / Staging / Production / Archived).
- Lineage: training run, data version, code commit.
- Metadata: input schema, eval metrics.

Promotion flow:

```
train → register (version N, stage=None)
  → eval → register_promote (stage=Staging)
  → shadow in prod → register_promote (stage=Production)
  → older → Archive
```

## Packaging

Model formats, ranked by portability:

| Format | Good |
|---|---|
| **ONNX** | Language-agnostic; runs in ONNX Runtime, CPU/GPU, edge |
| **TorchScript** | PyTorch-specific; compiled |
| **SavedModel / Keras** | TensorFlow |
| **Pickle / CloudPickle** | Python-only; version-brittle |
| **Custom** | Whatever framework serialization |

Prefer ONNX when possible for serving flexibility.

## Containers for training and serving

- Use base images matching your ML framework (PyTorch official,
  NVIDIA CUDA, TensorFlow).
- Pin versions of framework and CUDA exactly.
- Multi-stage builds: training image ≠ serving image.
- Serving image: minimal; model + inference code only.

## CI/CD

### CI — every PR

- Pre-commit (black, ruff, mypy).
- Unit tests on code, transforms, dataset stats.
- Smoke train (< 10 min).
- Offline eval on CI dataset.
- Build container image.

### CD — on merge

- Trigger full retrain (if data / code changed enough).
- Register new model version.
- Shadow / canary deploy.
- Watch metrics.
- Promote if healthy.

### Retraining triggers

- **Calendar** — weekly/nightly.
- **Data volume** — N new labeled rows.
- **Drift** — input or prediction distribution shifted past
  threshold.
- **Metric regression** — production metric dipped below SLO.

## Reproducibility checklist

- Code commit SHA.
- Data version / snapshot ID.
- Exact dependency versions (lockfile).
- Random seed.
- Hardware spec (GPU type, driver, CUDA).
- Run ID in MLflow/W&B.
- Container image digest.

Without all of these, "rerun last week's model" may not match
anymore.

## Data lineage

Who produced this prediction from which inputs?

- Track at table level (dbt, OpenLineage).
- Track at row level for audit-critical use (healthcare, finance).
- Inference-time: attach `model_version + feature_snapshot` to
  every prediction.

## Cost control

- **Tag every run** with team/project/cost-center.
- **Cap runaway jobs** with wall-clock + GPU-hour limits.
- **Spot / preemptible** for training when checkpointing supports
  it (PyTorch Lightning `ModelCheckpoint` makes this easy).
- **Right-size** inference — don't serve a CPU-fast model on GPU.
- **Aggregate predictions** where possible; avoid online calls for
  stable features.

## Small-team starter stack

For a 2–5 person ML team:

- **Storage**: S3 + Parquet / Delta Lake.
- **Orchestrator**: Prefect or Dagster.
- **Experiment tracking**: MLflow (self-hosted on a VM).
- **Registry**: MLflow.
- **Training**: Lightning (PyTorch) or sklearn.
- **Serving**: BentoML on Fargate / Cloud Run.
- **Monitoring**: Evidently AI + Grafana.

No K8s required. Ship production models in weeks.
