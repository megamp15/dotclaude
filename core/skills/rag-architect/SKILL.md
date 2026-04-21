---
name: rag-architect
description: End-to-end RAG (retrieval-augmented generation) system design — chunking, embeddings, vector stores, hybrid search (BM25 + dense), rerankers, evaluation (Ragas), citation discipline, freshness, and the hard parts everyone underestimates (chunk boundaries, query rewriting, eval sets). Distinct from `fine-tuning-expert` (weights) and `prompt-engineer` (prompts).
source: core
triggers: /rag, retrieval augmented generation, vector database, embedding model, chunking strategy, hybrid search, BM25, reranker, Cohere rerank, cross encoder, pgvector, Qdrant, Milvus, Weaviate, Pinecone, LangChain, LlamaIndex, Ragas, hallucination, citation, knowledge base Q&A
ported-from: https://github.com/Jeffallan/claude-skills/tree/main/skills/rag-architect
ported-at: 2026-04-17
ported-sha: main
adapted: true
---

# rag-architect

Deep expertise on retrieval-augmented generation systems. Activates
when the work is about wiring LLMs to private/external knowledge —
not about weights (fine-tuning) or prompts alone.

> **See also:**
>
> - `core/skills/fine-tuning-expert/` — when to change weights
>   instead of / in addition to retrieval
> - `core/skills/prompt-engineer/` — prompt-side quality
> - `core/skills/llm-serving/` — inference infra (vLLM, TGI, Ollama)
> - `core/skills/ml-pipeline/` — data ingestion / ETL around RAG
> - `core/rules/llm-safety.md` — output handling, injection

## When to use this skill

- Designing a new RAG system from scratch.
- Existing RAG hallucinates / misses / cites wrong docs.
- Choosing embedding model, vector DB, chunking, reranker.
- Adding hybrid search (BM25 + vector).
- Wiring evaluation with Ragas / custom metrics.
- Scaling retrieval from 10k → 10M chunks.
- Supporting multilingual / code / tabular retrieval.

## References (load on demand)

- [`references/chunking-and-embeddings.md`](references/chunking-and-embeddings.md)
  — chunk sizing, overlap, semantic splitting, embedding model
  selection (by domain, language, dimension), metadata strategy,
  hierarchical retrieval.
- [`references/retrieval-and-reranking.md`](references/retrieval-and-reranking.md)
  — dense vs. sparse vs. hybrid, query rewriting, HyDE,
  filtering/metadata, rerankers (Cohere, cross-encoder, LLM
  judges), top-k tuning.
- [`references/evaluation.md`](references/evaluation.md) —
  building an eval set, Ragas metrics (faithfulness, answer
  relevance, context precision / recall), latency SLOs, A/B
  tracking, grounding and citation discipline.

## Core workflow

1. **Start with the question.** What will users actually ask?
   Gather 30–50 real queries from users / PM / support. This is
   the eval set foundation.
2. **Name the sources.** Fixed corpus? Growing knowledge base?
   Multiple tenants? Access-controlled?
3. **Design ingestion first.** How does data enter? How often? How
   do you update it? This usually dominates; retrieval quality
   depends on it.
4. **Chunk for answers, not for paragraphs.** Chunks should be
   self-contained enough that one alone can answer a question.
5. **Hybrid by default.** Dense + BM25. Dense alone misses exact
   terms (names, IDs, codes); BM25 alone misses semantic rephrasing.
6. **Rerank.** Cross-encoder or Cohere Rerank on top-N retrieval.
   Usually +10-20% recall-at-k.
7. **Cite everything.** Every claim in the answer → chunk ID.
   Enforce this in the prompt and verify in eval.
8. **Evaluate continuously.** Ragas or hand-rolled metrics on the
   eval set. Re-run on every change.

## Defaults

| Question | Default |
|---|---|
| Embedding model (general English) | OpenAI `text-embedding-3-large` or `bge-large-en-v1.5` (OSS) |
| Embedding model (multilingual) | `bge-multilingual-gemma2` or `multilingual-e5-large` |
| Embedding model (code) | `voyage-code-3` or `jina-embeddings-v2-base-code` |
| Vector DB (start) | PostgreSQL + `pgvector` for < 5M chunks |
| Vector DB (scale) | Qdrant for self-host; Pinecone / Vertex for managed |
| Chunk size | 500–1000 tokens, 100-token overlap |
| Splitter | Recursive char → sentence → token splitter with semantic boundaries |
| Retrieval | Hybrid (dense + BM25), k=20 before rerank |
| Reranker | Cohere Rerank 3 or `bge-reranker-v2-m3` (OSS, cross-encoder) |
| Post-rerank top-k for context | 3–5 (tune via eval) |
| Answer LLM | Start with Claude 3.5 Sonnet / GPT-4o; move to smaller once eval plateaus |
| Framework | LlamaIndex or bare-bones (LangChain for prototyping only) |
| Eval | Ragas for core metrics; custom per-domain checks |
| Query rewriting | LLM rewrite for ambiguous / conversational queries; HyDE for research-type |
| Citation format | `[chunk_id:n]` inline; render doc + anchor in UI |
| Freshness | Incremental reindex daily; full reindex weekly |
| Access control | Pre-filter by tenant/user before embedding search |

## Anti-patterns

- **Chunking by arbitrary character count.** 1000 chars splits
  mid-sentence; splits at token boundaries preserve meaning.
- **Dense-only retrieval.** Fails on exact-match needs (SKUs, IDs,
  error codes, class names).
- **Skipping the reranker.** First-stage retrieval is noisy. A
  cross-encoder rerank routinely recovers 15–30% recall.
- **No eval set.** You're flying blind. Impossible to know if
  your next change helped.
- **Using LangChain as the production framework.** Great for
  prototypes; too much indirection and breaking changes for prod.
  LlamaIndex or direct API calls scale better.
- **Embedding the entire document as one vector.** Except for tiny
  docs, retrieval collapses to one hit regardless of which section
  is relevant.
- **Indexing raw PDFs via OCR without cleanup.** OCR garbage in =
  garbage embeddings out.
- **Returning the raw LLM answer without citations.** Hallucination-
  resistant systems force the model to cite; hallucinations drop
  dramatically.
- **Single embedding model across languages.** Multilingual needs a
  multilingual model.
- **Ignoring metadata.** Filtering by date / tenant / type before
  semantic search is usually the biggest quality lever.
- **Cross-tenant leakage.** Multi-tenant RAG must filter *before*
  retrieval, not after. A bug in the filter is a data breach.

## Output format

For a RAG design:

```
Corpus:           <what's in it, size, growth rate>
Access model:     <public / tenant / user; controls>
Canonical query:  <example + intent>

Ingestion:        <source → parser → chunker → embedder>
Store:            <vector DB + tables/schemas>
Retrieval:        <dense + BM25 + filter + rerank>
Generation:       <LLM + prompt template + citation format>
Eval set:         <size, source, metrics tracked>
Freshness:        <update cadence + incremental strategy>

Risks / open:
  - <thing to revisit>
```

For a triage of a bad RAG system:

```
Symptom:          <observed quality issue>
Likely causes (in order):
  1. <ingestion / chunking issue>
  2. <retrieval / rerank issue>
  3. <prompt / generation issue>
Diagnostic:       <how to confirm — usually eval on N queries>
Fix order:        <cheapest-first>
```

## The cost axis

| Stage | Unit cost | Optimization |
|---|---|---|
| Embedding (ingest) | $/1M tokens | Do once; cache; rarely re-embed |
| Embedding (query) | $/query | Tiny; negligible |
| Vector search | $/server-hour | Size by corpus; shard for scale |
| Rerank | $/1k ops or $/hour | Batch; small cross-encoder often fine |
| LLM generation | $/1M tokens | Shrink context; prompt caching if supported |

Retrieval-quality wins reduce generation cost by shrinking context.
Cheap lever.

## When RAG is wrong

RAG is the wrong tool when:

- **The model's base knowledge is fine.** Adding retrieval adds
  latency and hallucination opportunity for no gain.
- **You need reasoning over structured data.** SQL / code-gen /
  function-calling is better.
- **The corpus is small and stable.** Fine-tune instead (or include
  as system prompt if truly small).
- **Users need one canonical answer from a source of truth.** A
  lookup table / structured search is better than a generative
  layer.

Prefer RAG when:

- Corpus is large and changing.
- Answers must be attributable to specific documents.
- Access control is per-document / per-tenant.
- Domain vocabulary is specialized (legal, medical, codebase-
  specific) but the generator doesn't need to be re-trained.
