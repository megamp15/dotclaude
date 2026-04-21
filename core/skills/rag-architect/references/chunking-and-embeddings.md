# Chunking and embeddings

Retrieval quality is upper-bounded by chunk quality. If the right
information isn't in any single chunk, no retriever can find it.

## Chunking strategies

### Fixed-size character/token chunks

- Simplest: every N tokens, overlap M tokens.
- Defaults: 500–1000 tokens / 100 token overlap.
- Works well for prose; fails on code, tables, structured docs.

### Sentence or paragraph chunks

- Split at sentence boundaries (spaCy, NLTK), group into
  `~target_size` chunks.
- Preserves semantic atoms; chunks are often cleaner than fixed
  tokens.

### Recursive character splitter (LangChain / LlamaIndex)

- Splits at the "biggest possible separator first": `\n\n` →
  `\n` → `. ` → ` ` → char.
- De facto default. Sound compromise.

### Semantic chunking

- Embed candidate boundaries; merge adjacent sentences that are
  semantically close, split where similarity drops.
- Tools: LlamaIndex `SemanticSplitterNodeParser`, Greg Kamradt's
  semantic chunker.
- Expensive at ingest; quality gains are real but modest (~5-10%
  recall).

### Structure-aware

- **Markdown:** split by headings; keep section hierarchy in
  metadata.
- **HTML:** split at `<h1>/<h2>/<h3>`; strip nav/footer;
  Readability-style extraction.
- **PDF:** use a real parser (Unstructured, Amazon Textract, Azure
  Document Intelligence, Docling). PDF-to-text naïvely loses tables
  and layout.
- **Code:** split by function/class; use AST-aware splitters
  (tree-sitter, `ast` in Python).
- **Tables:** either serialize to markdown + embed row-by-row, or
  store separately and retrieve structurally.

### Hierarchical chunking

- Index both **small "answer" chunks** (for precision) and **larger
  "context" chunks** (for completeness).
- Retrieve small chunks; look up parent context for the final LLM
  input.
- Tools: LlamaIndex `HierarchicalNodeParser`.

### Parent-document retrieval

- Store small child chunks in the vector DB; each carries a
  `parent_id`.
- At generation time, look up the full parent document (or
  paragraph).
- Avoids chunk-scale context fragmentation without paying the
  embedding cost of embedding long parents.

## Chunk size guidance

| Task | Chunk size |
|---|---|
| Factual Q&A over docs | 300–500 tokens |
| Long-form summarization | 800–1500 tokens |
| Code search | Whole function, or 500 tokens |
| Support / policy docs | 500–800 tokens; keep boundaries on logical sections |
| Research paper | 500 tokens within each section |

Overlap:

- 10–20% of chunk size.
- Higher overlap helps when answers span boundaries; lower reduces
  storage.

## Metadata — free quality wins

Every chunk carries:

- `doc_id`, `chunk_id`, `title`, `url`, `section`.
- `source`, `language`, `date`.
- `tenant_id`, `acl` (if multi-tenant / access-controlled).
- Domain-specific tags: `product=...`, `jurisdiction=...`, `version=...`.

Use metadata for **pre-filtering** before vector search:

```python
# Pseudo: only search user's tenant, only recent docs, then vector.
hits = store.search(
    query_vec,
    filter={"tenant_id": user.tenant_id, "date": {"$gte": "2024-01-01"}},
    k=20,
)
```

Metadata filtering is usually the **single biggest quality lever**
after hybrid search.

## Embedding model selection

### Benchmarks

Main reference: **MTEB** (Massive Text Embedding Benchmark). Sort
by task type matching yours (retrieval, clustering, classification).

### General English, best quality

- Commercial: OpenAI `text-embedding-3-large` (3072d),
  `text-embedding-3-small` (1536d).
- OSS: `bge-large-en-v1.5` (1024d), `mxbai-embed-large-v1` (1024d),
  `nomic-embed-text-v1.5` (768d, supports variable dim via
  Matryoshka).
- SOTA-ish: `stella_en_1.5B_v5`, `gte-large-en-v1.5`.

### Multilingual

- `bge-multilingual-gemma2` (large, strong).
- `multilingual-e5-large` (well-proven).
- OpenAI `text-embedding-3-*` (decent multilingual).
- Cohere `embed-multilingual-v3`.

### Code

- `voyage-code-3` (commercial, SOTA).
- `jina-embeddings-v2-base-code` (OSS).
- CodeT5+/StarCoder embeddings via their models.
- `all-MiniLM-L6-v2` is a reasonable baseline.

### Choosing by size

- **Small** (384–768d) — faster, cheaper to store/search, some
  quality loss. Use when corpus is large (>10M chunks).
- **Large** (1024–3072d) — better recall, more storage/compute.
  Use when corpus fits and quality matters.

Matryoshka embeddings (e.g., `nomic-embed-text-v1.5`,
`text-embedding-3-large`) let you truncate the vector — trade
quality for speed dynamically.

### Quantization

Int8 quantization halves storage/latency with ~1% quality loss.
Supported by Qdrant, Pinecone, FAISS. Default on for scale.

## Embedding discipline

- **Embed the text, not metadata.** Metadata goes in the payload;
  the embedding is the semantic signal.
- **Pre-process consistently.** Same normalization at ingest and
  query: lowercase, Unicode normalize, whitespace collapse — whatever
  you do.
- **Truncate input to model max.** Most models max at 512 tokens;
  feeding 2000 tokens silently truncates or errors.
- **Use the model's recommended instruction prefix.** E.g., BGE:
  `"Represent this sentence for searching relevant passages: "`
  prepended to queries (not docs). Check your model's card.
- **Don't embed boilerplate.** Headers/footers/navigation should be
  stripped before embedding — they add noise.

## Multi-vector approaches

### ColBERT / late interaction

- One vector per token; query-token vs. doc-token max-sim score.
- Higher quality at much higher storage cost. Tools:
  `ColBERT-AI`, `RAGatouille`.
- Worth considering for high-precision needs and <10M chunks.

### Sparse-dense hybrid embeddings

- SPLADE: sparse vector over vocabulary, learned. Combines with
  BM25-like behavior but semantically.
- Hybrid with a dense vector is strong.

Both are advanced — start with dense + BM25 hybrid, move to these
if eval shows meaningful headroom.

## Contextual embeddings (Anthropic pattern)

Prepend a short LLM-generated summary of the doc to each chunk
before embedding:

```
<doc summary in 2 sentences>
<chunk text>
```

The resulting embedding carries doc-level context. Anthropic
reported ~35-50% retrieval accuracy improvement in their cookbook.
Cost: one LLM call per chunk at ingest.

## Freshness / incremental updates

Design for updates from day one:

- Idempotent ingestion keyed by `(source_id, version)`.
- Upsert, not re-insert; delete stale.
- Incremental job: "what's changed since last run?"
- Full reindex weekly to catch drift.

Don't rebuild from scratch on every change — cost and latency
both suffer.

## Multi-tenant / access control

- **Shared index + filter by tenant metadata.** Cheapest;
  filtering is effectively free if the DB supports payload
  filtering first.
- **Namespace per tenant.** Some DBs (Pinecone, Qdrant) offer
  namespaces; isolation is better.
- **Index per tenant.** Strongest isolation; operationally
  heaviest.

For enterprise RAG: **filter before semantic search**. A missing
filter in a query path = data leak.

Pre-compute ACLs per chunk at ingest (`acl: ["team-a", "team-b"]`)
and filter to a user's groups at query.
