# Retrieval and reranking

## Dense vs. sparse vs. hybrid

| Approach | Strength | Weakness |
|---|---|---|
| **Dense** (vector) | Semantic paraphrase; intent | Exact tokens (IDs, SKUs, error codes, rare names) |
| **Sparse** (BM25) | Exact / rare terms; interpretable | Synonyms, rephrasing |
| **Hybrid** | Both | Tuning required |

**Hybrid is the baseline for anything real.** Academic papers
consistently show 10–30% recall-at-k improvement over dense-only.

### Hybrid fusion

- **Reciprocal Rank Fusion (RRF)** — combine ranks, ignoring raw
  scores: `score(d) = Σ 1 / (k + rank_i(d))`. Default `k = 60`.
  Robust, simple.
- **Weighted score fusion** — normalize then weighted sum. Requires
  score calibration per query; fragile.
- **Re-rank both lists together** — feed top-N-each to a cross-
  encoder, take its ordering. Usually best; more compute.

## BM25 implementation

- **Elasticsearch / OpenSearch** — production BM25, built-in
  analysis.
- **Qdrant** — supports BM25 natively in recent versions.
- **PostgreSQL `ts_rank_cd`** on a `tsvector` column — fine for
  moderate scale.
- **Tantivy / Vespa** — higher-performance options.
- **LlamaIndex `BM25Retriever`** — in-memory; fine for prototypes.

## Vector database choices

| DB | When |
|---|---|
| **pgvector** (Postgres) | Already have Postgres; <5M chunks; single-tenant; simple ops |
| **Qdrant** | Self-host at scale; filters; hybrid built-in; good Rust core |
| **Milvus / Zilliz** | Large scale (100M+); mature |
| **Weaviate** | Opinionated schema; GraphQL; good built-in hybrid |
| **Pinecone** | Fully managed; predictable; pricey at scale |
| **Chroma** | Prototypes; local dev |
| **LanceDB** | Embedded; serverless-friendly; great for prototypes |
| **Elastic / OpenSearch** | Have a search cluster already; want BM25 + vector in one place |
| **Vertex / AWS Kendra / Vespa Cloud** | Managed enterprise |

Defaults:

- Starting: **pgvector** (if you have Postgres) or **Qdrant**.
- Growing: **Qdrant** self-host or **Pinecone** managed.
- Enterprise: existing search infra + vector extension (OpenSearch
  k-NN, Elastic dense_vector).

## Query rewriting

Most users' queries are suboptimal. Rewriting is high-ROI.

### Simple rewrite

LLM call to normalize / expand:

```
User: "how do I fix the 401 error on login"
Rewrite: "steps to fix HTTP 401 unauthorized error on login endpoint,
         auth configuration, bearer token, session cookie"
```

Useful for ambiguous / conversational inputs.

### HyDE (Hypothetical Document Embeddings)

- Ask the LLM: "write a paragraph that answers this question".
- Embed the **hypothetical answer**, not the query.
- Search vector space for real docs matching that paragraph.

Works when queries are short and answers are long (research
questions). Adds a round-trip; skip for latency-sensitive cases.

### Multi-query retrieval

- Generate 3–5 paraphrases of the query.
- Retrieve for each.
- Fuse (RRF) results.

Strong for ambiguous queries; pay N× embedding+search.

### Step-back prompting

- For complex questions, ask the LLM for a *broader* question first
  ("what's the underlying principle?"), retrieve on that, then
  answer the specific.

## Metadata filtering

Do this first:

```python
hits = store.search(
    query_vec,
    filter={
        "tenant_id": user.tenant_id,
        "type": "policy_doc",
        "date": {"$gte": "2024-01-01"},
    },
    k=20,
)
```

Rules:

- **Filter before semantic search** — post-filtering wastes
  retrieval slots.
- **Use native payload filtering** of your DB (Qdrant payload,
  pgvector + WHERE, Elastic filter). Application-side filtering is
  too slow for large indices.
- **Validate the filter against the user** — never filter "whatever
  the UI asked for". Tenant / ACL comes from the authenticated
  identity.

## Rerankers

First-stage retrieval (dense + BM25) is fast but noisy. A reranker
re-scores top-N with a better (slower) model.

### Cross-encoder rerankers

- Input: `(query, document)` pair; output: relevance score.
- Slow per pair; fine for N=20–50.
- OSS: `bge-reranker-v2-m3`, `jina-reranker-v2-base-multilingual`,
  `ms-marco-MiniLM-L-12-v2`.
- Commercial: **Cohere Rerank 3** — usually the best off-the-shelf
  option, supports long contexts, multilingual.

### LLM judge reranker

- Small LLM scores each `(query, document)` as "relevant 0–10".
- More expensive but interpretable.
- Useful in domain-specific settings where general rerankers
  underperform.

### Rerank pipeline

```
  ┌─ dense (k=20) ──┐
  ├─ BM25  (k=20) ──┼── RRF fuse ── rerank (top 50) ── top 5 to LLM
  └─ filter applied ┘
```

Tune top-5 via eval. 3 is usually too few; 10 is usually too many.

## The "lost-in-the-middle" effect

LLMs attend most to the beginning and end of context. Middle chunks
get less weight.

Mitigations:

- Put the top-ranked chunks first *and* last.
- Keep context small (3–5 chunks).
- Use models with better long-context performance (Claude 3.5
  Sonnet, GPT-4o, Gemini 1.5) — they exhibit this less.

## Prompt template

```
You are an assistant that answers questions using the provided
context. If the answer isn't in the context, say "I don't know".
Cite every claim with [chunk_id:N].

Context:
[chunk_id:1] <text>
[chunk_id:2] <text>
[chunk_id:3] <text>

Question: <q>

Answer (with citations):
```

Rules:

- **Force citation syntax.** Post-process to verify every claim
  maps to a real chunk ID.
- **Allow "I don't know".** Without this, models hallucinate to
  satisfy the prompt.
- **Short, focused** context. Padding context with "relevant-ish"
  chunks degrades quality.

## Top-k tuning

Evaluate at multiple k values:

- Low k (2–3) — highest precision, lowest coverage.
- Medium k (5–8) — typical production balance.
- High k (10–20) — for explore-y workloads; uses more context.

Metric to watch: **recall@k** (what fraction of the gold chunks
ended up in top-k). Pick the smallest k where recall@k plateaus.

## Generation time

- **Stream** the answer; users care about time-to-first-token.
- **Cache** prompt prefix if supported (Anthropic, OpenAI caching
  APIs, vLLM prefix caching).
- **Small model for simple queries**, large for complex. Route via
  a classifier or intent detector.

## Latency budget example

Total target: **2 seconds p95**

| Stage | Budget |
|---|---|
| Query embedding | 50 ms |
| Vector search | 50 ms |
| BM25 search | 30 ms |
| Fusion + filter | 10 ms |
| Rerank (N=20) | 150 ms |
| LLM generation | 1700 ms |

Optimize retrieval first (CPU-bound, parallel-safe); LLM is the
big cost.

## Caching

- **Query embeddings** — cache by normalized query text (dedup).
- **Retrieval results** — cache by `(query, filter, k)`; short TTL
  (minutes) for freshness.
- **LLM answers** — cache by `(retrieved_chunks, question)` hash.
  Invalidate on reindex.

Semantic caching: cache by query *embedding similarity*. Rarely
hits without very precise thresholds; more miss than hit in
practice.

## When to add a conversational layer

- Multi-turn Q&A requires query rewriting to resolve references
  ("and what about the second one?").
- Rewrite: send the last N turns + current question to an LLM;
  output a standalone question; retrieve on that.
- Keep session history short (last 5 turns usually).
