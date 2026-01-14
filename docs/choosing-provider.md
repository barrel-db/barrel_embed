# Choosing a Provider

This guide helps you select the right embedding provider for your use case.

## Quick Decision Tree

```
Need image embeddings?
  └─ Yes → CLIP
  └─ No ↓

Need sparse vectors for hybrid search?
  └─ Yes → SPLADE
  └─ No ↓

Need token-level matching?
  └─ Yes → ColBERT
  └─ No ↓

Can use external API?
  └─ Yes → OpenAI (best quality)
  └─ No ↓

Have Ollama installed?
  └─ Yes → Ollama (recommended)
  └─ No ↓

Need lightweight install?
  └─ Yes → FastEmbed (~100MB)
  └─ No → Local (~2GB with PyTorch)
```

## Provider Comparison

### Dense Embedding Providers

| Provider | Quality | Speed | Install Size | Dependencies | Offline |
|----------|---------|-------|--------------|--------------|---------|
| **OpenAI** | ★★★★★ | Fast | None | API key | No |
| **Ollama** | ★★★★☆ | Fast | ~2GB (model) | Ollama server | Yes |
| **Local** | ★★★★☆ | Medium | ~2GB | Python, PyTorch | Yes |
| **FastEmbed** | ★★★★☆ | Fast | ~100MB | Python, ONNX | Yes |

### Specialized Providers

| Provider | Type | Output | Best For |
|----------|------|--------|----------|
| **SPLADE** | Sparse | `{indices, values}` | Hybrid search, keyword expansion |
| **ColBERT** | Multi-vector | `[[float]]` per token | Fine-grained semantic matching |
| **CLIP** | Cross-modal | `[float]` | Image-text search |

## When to Use Each Provider

### OpenAI

**Best for:** Production systems requiring highest quality

```erlang
{openai, #{model => <<"text-embedding-3-small">>}}
```

✅ **Use when:**

- Quality is the top priority
- You have budget for API costs
- Low latency to OpenAI servers
- Don't need offline capability

❌ **Avoid when:**

- Data privacy is critical (data sent to API)
- Need offline/air-gapped operation
- High volume with tight budget

---

### Ollama

**Best for:** Local deployment without Python complexity

```erlang
{ollama, #{url => <<"http://localhost:11434">>, model => <<"nomic-embed-text">>}}
```

✅ **Use when:**

- Want local inference without Python
- Already using Ollama for LLMs
- Need good quality with simple setup
- Want to avoid API costs

❌ **Avoid when:**

- Can't install Ollama
- Need embedded solution (no server)
- Memory constrained (models loaded in RAM)

---

### Local (sentence-transformers)

**Best for:** Full control, access to any HuggingFace model

```erlang
{local, #{model => "BAAI/bge-base-en-v1.5"}}
```

✅ **Use when:**

- Need specific HuggingFace models
- Already have PyTorch environment
- Want maximum model flexibility
- Need fine-tuning capability

❌ **Avoid when:**

- Disk space is limited (~2GB install)
- PyTorch dependency is problematic
- Need fastest possible inference

---

### FastEmbed

**Best for:** Lightweight local inference

```erlang
{fastembed, #{model => "BAAI/bge-small-en-v1.5"}}
```

✅ **Use when:**

- Need local inference with small footprint
- Don't want PyTorch dependency
- Deploying to resource-constrained environments
- Quality similar to sentence-transformers is acceptable

❌ **Avoid when:**

- Need models not supported by FastEmbed
- Need absolute maximum quality

---

### SPLADE

**Best for:** Hybrid lexical-semantic search

```erlang
{splade, #{model => "prithivida/Splade_PP_en_v1"}}
```

✅ **Use when:**

- Building hybrid search (BM25 + semantic)
- Need keyword expansion (synonyms, related terms)
- Want efficient inverted index storage
- Combining with dense embeddings

❌ **Avoid when:**

- Only need dense vector search
- Memory constrained (sparse→dense is expensive)
- Don't have hybrid search infrastructure

**Example use case:** E-commerce search where users type product names (lexical) but also want semantic matches.

---

### ColBERT

**Best for:** Fine-grained passage retrieval

```erlang
{colbert, #{model => "colbert-ir/colbertv2.0"}}
```

✅ **Use when:**

- Single-vector similarity isn't precise enough
- Building QA or passage retrieval systems
- Need token-level relevance signals
- Documents have varying relevant sections

❌ **Avoid when:**

- Storage is limited (multiple vectors per doc)
- Simple semantic similarity is sufficient
- Real-time latency is critical

**Example use case:** Legal document search where specific clauses matter more than overall document similarity.

---

### CLIP

**Best for:** Image and cross-modal search

```erlang
{clip, #{model => "openai/clip-vit-base-patch32"}}
```

✅ **Use when:**

- Searching images with text queries
- Finding visually similar images
- Building multi-modal applications
- Need zero-shot image classification

❌ **Avoid when:**

- Only working with text
- Don't need image capabilities

**Example use case:** Stock photo search, content moderation, visual product search.

## Combining Providers

### Provider Chain (Fallback)

Use multiple providers for high availability:

```erlang
#{embedder => [
    {ollama, #{url => <<"http://localhost:11434">>}},
    {openai, #{}},
    {local, #{}}
]}
```

If Ollama fails → try OpenAI → fall back to local Python.

### Hybrid Search (SPLADE + Dense)

Combine sparse and dense for best retrieval:

```erlang
%% Sparse for lexical matching
{ok, SpladeState} = barrel_embed:init(#{embedder => {splade, #{}}}).

%% Dense for semantic matching
{ok, DenseState} = barrel_embed:init(#{embedder => {ollama, #{...}}}).

%% Query both and combine scores
SparseScore = search_sparse(Query, SpladeState),
DenseScore = search_dense(Query, DenseState),
FinalScore = 0.3 * SparseScore + 0.7 * DenseScore.
```

## Performance Benchmarks

Approximate performance on typical hardware (results vary):

| Provider | First Request | Subsequent | Batch (100 texts) |
|----------|---------------|------------|-------------------|
| OpenAI | 200ms | 100ms | 500ms |
| Ollama | 2s (model load) | 50ms | 2s |
| Local | 5s (model load) | 100ms | 3s |
| FastEmbed | 3s (model load) | 50ms | 2s |

## Summary Table

| Use Case | Recommended Provider |
|----------|---------------------|
| Production, best quality | OpenAI |
| Local, simple setup | Ollama |
| Local, any HF model | Local |
| Local, lightweight | FastEmbed |
| Hybrid search | SPLADE + Dense |
| Passage retrieval, QA | ColBERT |
| Image search | CLIP |
| High availability | Provider chain |
