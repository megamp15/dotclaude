# Evaluation

A RAG system you don't evaluate doesn't improve. Or rather: you
can't tell when it gets worse.

## The eval set

### How to build one

1. **Gather 30–50 real queries** from: users, support tickets, PM
   intuition, smoke tests. Must reflect actual usage.
2. **For each query, record**:
   - The gold answer (what a human expert would write).
   - The gold chunks (which documents should be cited).
3. **Store** in a versioned file (JSONL). Each entry is stable and
   the set grows over time.

```jsonl
{"id": "q001", "query": "How do I reset my password?", "gold_chunks": ["doc:auth/pw-reset:0", "doc:auth/pw-reset:1"], "gold_answer": "Visit /reset, enter email, click link..."}
```

### Scaling the eval set

- Start with 30 hand-written queries.
- Grow to 100–500 with spot-checking of new queries.
- Beyond that: **synthetic generation** (LLM reads chunks, makes
  queries about them) with human spot-check. Tools: Ragas
  `TestsetGenerator`.

### Never evaluate on queries used in prompt tuning

Hold out a test set. Ragas helps manage this.

## Core metrics

### Retrieval metrics (no LLM needed)

- **Recall@k** — fraction of gold chunks in top-k retrieved.
  Primary indicator. Target: >0.8 at k=5 once mature.
- **MRR (Mean Reciprocal Rank)** — 1 / rank of first relevant chunk.
- **NDCG@k** — Discounted Cumulative Gain; weights higher ranks.
- **Hit@k** — 1 if any gold chunk in top-k, else 0.

### Generation metrics (require LLM judge)

- **Faithfulness** — answer supported by retrieved context?
  (0 if hallucinated.)
- **Answer relevance** — does the answer address the query?
- **Context relevance** — is the retrieved context on-topic for
  the query?
- **Citation precision** — do cited chunks actually support the
  claim?
- **Citation recall** — does every claim have a citation?

## Ragas

[Ragas](https://github.com/explodinggradients/ragas) implements
the standard RAG metrics.

```python
from ragas import evaluate
from ragas.metrics import (
    faithfulness,
    answer_relevancy,
    context_precision,
    context_recall,
)
from datasets import Dataset

result = evaluate(
    dataset=Dataset.from_dict({
        "question": [...],
        "answer": [...],
        "contexts": [...],       # list of retrieved chunk texts
        "ground_truth": [...],   # gold answer
    }),
    metrics=[
        faithfulness,
        answer_relevancy,
        context_precision,
        context_recall,
    ],
)
```

Metric interpretations:

- **faithfulness** — fraction of answer claims supported by context.
  Target >0.9.
- **answer_relevancy** — how well the answer matches the question's
  intent. Target >0.85.
- **context_precision** — fraction of retrieved chunks that are
  relevant. Target >0.7 (higher means cleaner retrieval).
- **context_recall** — fraction of the gold answer covered by
  retrieved context. Target >0.8.

## Custom domain metrics

Ragas's defaults are generic. Add checks that reflect your domain:

- **Medical**: does the answer cite a source from the approved
  formulary?
- **Legal**: are all statutes referenced accurate and current?
- **Customer support**: does the answer match the action the
  agent would actually take?
- **Codebase Q&A**: does cited code actually exist in the repo at
  that line range?

Write these as Python assertions or LLM-judge prompts; log per-
query.

## Grounding enforcement

Post-process answers to verify every claim:

```python
def verify_citations(answer: str, retrieved: list[Chunk]) -> bool:
    claims = split_into_claims(answer)
    for claim in claims:
        citations = extract_citations(claim)    # [chunk_id:N]
        if not citations:
            return False
        for c in citations:
            chunk = retrieved[int(c)]
            if not llm_judge_supports(claim, chunk):
                return False
    return True
```

Log cases where verification fails; show as "uncertain" to users.

## A/B testing in production

- **Shadow traffic** — run new retrieval config against 10% of
  queries; log metrics; don't show results to users.
- **Shadow then graduate** — once metrics are stable, switch
  default.
- **Online metrics** — thumbs up/down; click-through on cited docs;
  "not helpful" feedback. Aggregate by query cluster.

## Latency tracking

p50 / p95 / p99 at each stage:

- Query embedding
- Vector search
- BM25 search
- Rerank
- LLM generation

Budget per stage; alert on regressions per the
`monitoring-expert` and `sre-engineer` skills.

## The quality-improvement loop

```
1. Measure on eval set  →  baseline metrics
2. Pick the worst metric  →  hypothesize cause
3. Change one thing       →  re-run eval
4. If better, deploy; else revert
5. Collect new real queries → expand eval set
```

Changes you test, one at a time:

- Chunk size / overlap.
- Embedding model.
- Reranker on/off; which reranker.
- Top-k.
- Query rewriting on/off.
- Metadata filter refinements.
- Prompt template changes.

**Don't change multiple at once.** Attribution becomes impossible.

## Failure modes to specifically track

- **Hallucinations** — count per 100 queries; faithfulness < 0.9.
- **"I don't know"** rate — too high = retrieval failing; too low =
  model hallucinating.
- **Slow queries** — p99 > SLO.
- **Stale content** — users flag answers based on outdated docs.
  Indicate reindex lag.
- **Cross-tenant leaks** — zero tolerance; pre-emptive synthetic
  tests that attempt access.

## Regression gate in CI

Run a small subset (20–50 queries) of the eval set on every PR.

```yaml
# Example GitHub Actions step
- run: python -m eval.ci --queries eval/ci-set.jsonl --baseline eval/baseline.json
```

Fail the PR if:

- Recall@k drops more than 5% on the subset.
- Faithfulness drops more than 3%.
- Latency p95 increases more than 20%.

## Tools

- **Ragas** — framework-agnostic metrics.
- **TruLens** — instrumentation + evals.
- **LangSmith** — LangChain's hosted eval / trace UI.
- **Arize Phoenix** — OSS tracing + eval UI.
- **Promptfoo** — generic prompt / RAG eval CLI, good for CI.
- **DeepEval** — unit-test-style LLM evaluation.

## Human-in-the-loop

Metrics can be wrong. Schedule periodic human review:

- Sample 10–20 queries per week.
- Rate answers 1–5 for quality.
- Compare against automatic scores.
- Calibrate the LLM judge prompts based on discrepancies.
