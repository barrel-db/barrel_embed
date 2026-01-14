# barrel_embed

Lightweight embedding generation for Erlang.

A standalone library for generating text and image embeddings with multiple provider backends and automatic fallback support.

## Features

- **Multiple Providers** - Ollama, OpenAI, local Python, FastEmbed, and more
- **Automatic Fallback** - Provider chain with seamless failover
- **Batch Processing** - Efficient batch embedding with configurable chunk size
- **Specialized Embeddings** - Sparse (SPLADE), multi-vector (ColBERT), cross-modal (CLIP)
- **Resource Management** - Python execution rate limiting

## Quick Example

```erlang
%% Initialize with Ollama
{ok, State} = barrel_embed:init(#{
    embedder => {ollama, #{
        url => <<"http://localhost:11434">>,
        model => <<"nomic-embed-text">>
    }}
}).

%% Generate embedding
{ok, Vector} = barrel_embed:embed(<<"Hello world">>, State).

%% Batch embedding
{ok, Vectors} = barrel_embed:embed_batch([<<"text1">>, <<"text2">>], State).
```

## Provider Overview

| Provider | Type | Best For |
|----------|------|----------|
| [Ollama](providers/ollama.md) | Dense | Local deployment, no Python needed |
| [OpenAI](providers/openai.md) | Dense | Production, high quality |
| [Local](providers/local.md) | Dense | Offline, full control |
| [FastEmbed](providers/fastembed.md) | Dense | Lightweight local inference |
| [SPLADE](providers/splade.md) | Sparse | Hybrid search, keyword expansion |
| [ColBERT](providers/colbert.md) | Multi-vector | Fine-grained semantic matching |
| [CLIP](providers/clip.md) | Cross-modal | Image-text search |

## Installation

Add to your `rebar.config`:

```erlang
{deps, [
    {barrel_embed, {git, "https://gitlab.enki.io/barrel-db/barrel-embed.git", {tag, "v0.1.0"}}}
]}.
```

## Next Steps

- [Getting Started](getting-started.md) - Installation and first steps
- [Providers](providers/index.md) - Detailed provider documentation
- [API Reference](api.md) - Complete API documentation
