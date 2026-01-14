# Providers Overview

barrel_embed supports multiple embedding providers, each with different characteristics and use cases.

## Dense Embedding Providers

Standard vector embeddings where each text produces a single fixed-dimension vector.

| Provider | Requirements | Dimensions | Best For |
|----------|-------------|------------|----------|
| [Ollama](ollama.md) | Ollama server | Model-dependent | Local deployment |
| [OpenAI](openai.md) | API key | 256-3072 | Production |
| [Local](local.md) | Python + sentence-transformers | Model-dependent | Offline use |
| [FastEmbed](fastembed.md) | Python + fastembed | Model-dependent | Lightweight local |

## Specialized Providers

Advanced embedding types for specific use cases.

| Provider | Type | Requirements | Best For |
|----------|------|-------------|----------|
| [SPLADE](splade.md) | Sparse | Python + transformers + torch | Hybrid search |
| [ColBERT](colbert.md) | Multi-vector | Python + transformers + torch | Fine-grained matching |
| [CLIP](clip.md) | Cross-modal | Python + transformers + torch + pillow | Image-text search |

## Choosing a Provider

### For Local Development

**Ollama** is recommended:

- No Python dependencies
- Easy model management
- Good performance

### For Production

**OpenAI** is recommended:

- Best quality embeddings
- High availability
- No infrastructure to manage

### For Offline/Air-gapped

**Local** or **FastEmbed**:

- No external API calls
- Full data privacy
- FastEmbed is lighter (~100MB vs ~2GB)

### For Specialized Use Cases

- **Hybrid search**: Use [SPLADE](splade.md) for sparse + dense combination
- **Passage retrieval**: Use [ColBERT](colbert.md) for token-level matching
- **Image search**: Use [CLIP](clip.md) for cross-modal embeddings

## Provider Chain

Configure fallback providers for high availability:

```erlang
#{embedder => [
    {ollama, #{url => <<"http://localhost:11434">>}},
    {openai, #{api_key => <<"sk-...">>}},
    {local, #{}}
]}
```

Providers are tried in order. If one fails, the next is attempted automatically.
