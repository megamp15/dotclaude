---
name: ml-pipeline
description: Production ML pipeline design — feature stores, training orchestration, model registry, batch vs. online inference, CI/CD for models, drift detection, and the full MLOps stack without vendor lock-in. Distinct from `fine-tuning-expert` (LLM-specific), `rag-architect` (retrieval), and `monitoring-expert` (general telemetry).
source: core
triggers: /ml-pipeline, MLOps, feature store, MLflow, model registry, Kubeflow, Airflow for ML, training pipeline, batch inference, online serving, model drift, data drift, feast, bentoML, Ray, SageMaker, Vertex AI, Metaflow, DVC
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/ml-pipeline
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# ml-pipeline

Deep expertise on productionizing machine-learning workloads — from
feature engineering to serving, with the operational concerns
(reproducibility, drift, CI/CD, cost) that non-ML-engineers often
underestimate.

> **See also:**
>
> - `core/skills/fine-tuning-expert/` — LLM training specifically
> - `core/skills/rag-architect/` — retrieval systems
> - `core/skills/monitoring-expert/` — general telemetry plumbing
> - `core/skills/sre-engineer/` — reliability posture
> - `stacks/python/skills/python-pro/` — Python performance basics
> - `stacks/kubernetes/skills/kubernetes-specialist/` — serving infra

## When to use this skill

- Designing the MLOps stack for a new team or project.
- Moving a notebook-based model to production for the first time.
- Choosing between SageMaker, Vertex, Databricks, Kubeflow, or
  self-hosted.
- Adding feature stores, experiment tracking, or a registry.
- Debugging training / serving skew, data drift, or cost.
- Setting up batch vs. online inference.

## References (load on demand)

- [`references/pipeline-stages.md`](references/pipeline-stages.md)
  — data ingestion, feature engineering, training orchestration,
  evaluation, registry, deployment — with tool choices at each.
- [`references/serving-and-monitoring.md`](references/serving-and-monitoring.md)
  — batch vs. online, model servers (BentoML, Triton, Ray Serve,
  TorchServe, KServe), shadow deployments, drift and performance
  monitoring.

## Core workflow

1. **Data first.** The pipeline's value is bounded by data quality.
   Invest in validation, schema enforcement, and backfills before
   fancy models.
2. **Reproducibility is the contract.** Same code + same data
   version = same model. DVC / LakeFS / Delta for data; MLflow for
   runs; git for code.
3. **Feature store only if you need it.** For 1 team, 1 model, skip.
   For many models sharing features, it's indispensable.
4. **Offline and online must match.** Training/serving skew is the
   top production failure. Serve features through the same code (or
   same spec) used in training.
5. **Small, frequent deployments.** Same ship discipline as software.
   Shadow, canary, rollback.
6. **Observability beyond accuracy.** Data drift, prediction drift,
   latency, feature missingness — same weight as model metrics.

## Defaults

| Question | Default |
|---|---|
| Orchestrator | Airflow / Dagster / Prefect for batch; Ray / Kubeflow for distributed training |
| Experiment tracker | MLflow (OSS, portable) |
| Model registry | MLflow Registry or SageMaker Model Registry |
| Feature store | Feast (OSS) or Tecton / Databricks FS (managed) |
| Data versioning | DVC or LakeFS or Delta Lake time travel |
| Training compute | Managed notebooks for dev → K8s/Ray for scale |
| Batch inference | Airflow / Dagster-driven Spark or Ray |
| Online serving | BentoML or Triton or KServe on K8s |
| Model format | ONNX for portability; native (.pt, .pkl via cloudpickle) for Python-only |
| CI for models | GitHub Actions + `pre-commit` + unit tests on data transforms + smoke train |
| CD for models | Shadow → canary → full; retrain gated on eval metrics |
| Monitoring | Prom + Evidently AI / WhyLabs for drift |
| Cost tracking | Per-run tags (team/project); nightly report |

## Anti-patterns

- **"Works in my notebook"** — path-dependent, kernel-dependent,
  non-reproducible. Make every data access and feature transform
  a function with tests.
- **Model file in git.** Large, binary, unversionable. Use a
  registry or object storage with a lineage record.
- **No eval set frozen in CI.** Model quality regressions slip
  through.
- **Training features diverge from serving.** A tiny difference
  (lowercasing, default values, rounding) destroys accuracy.
- **Single giant monolithic DAG.** Becomes unmaintainable;
  individual stages hard to re-run.
- **No rollback plan.** "We retrained and accuracy dropped" with
  no way back = incident.
- **Treating the model as the product.** The pipeline that
  produces, updates, and serves the model **is** the product.
- **One person owns the pipeline.** Bus factor = 1.

## Output format

For a pipeline design:

```
Problem:             <business question>
Latency target:      <offline / minutes / seconds / real-time>
Data sources:        <tables / streams / APIs>
Refresh cadence:     <daily / hourly / streaming>

Stages:
  Ingest:            <tool + schema>
  Feature eng:       <tool + store?>
  Train:             <framework + compute>
  Eval:              <metrics + gate>
  Register:          <registry + versioning>
  Deploy:            <batch / online + canary>
  Monitor:           <drift + perf + biz metric>

Data versioning:     <tool>
Experiment tracking: <tool>
CI/CD:               <triggers + gates>

Cost model (rough):  <compute + storage per month>
```
