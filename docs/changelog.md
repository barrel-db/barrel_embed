# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-01-27

### Added

#### Cloud Providers

- `cohere` - Cohere Embed API with input type optimization
- `voyage` - Voyage AI for RAG and domain-specific embeddings (code, law, finance)
- `jina` - Jina AI with 8K context and free tier
- `mistral` - Mistral AI with EU data residency
- `azure` - Azure OpenAI for enterprise compliance
- `bedrock` - AWS Bedrock (Titan, Cohere models) with IAM and API key auth
- `vertex` - Google Vertex AI for GCP ecosystem

#### Documentation

- Provider comparison guide (`docs/choosing-provider.md`)
- Developer guide for adding cloud providers (`docs/dev/adding-provider.md`)
- Individual documentation pages for all cloud providers

#### Tooling

- `scripts/setup_python_venv.sh` for one-command Python venv setup

#### Python Engine

- Async request multiplexing for concurrent embeddings
- Improved error handling and logging

### Changed

- Updated hackney dependency to 2.0.1 for HTTP/2 support
- Provider init now properly loads modules before checking exports
- Removed redundant `application:ensure_all_started(hackney)` from providers (hackney starts via app.src)

## [0.1.0] - 2026-01-14

### Added

- Initial release extracted from barrel_vectordb
- Core embedding coordinator (`barrel_embed`) with provider chain and fallback support
- Provider behaviour (`barrel_embed_provider`) for implementing custom providers
- Python execution rate limiter (`barrel_embed_python_queue`)

#### Providers

- `local` - Local Python with sentence-transformers
- `ollama` - Ollama server API (supports both `/api/embed` and `/api/embeddings`)
- `openai` - OpenAI Embeddings API
- `fastembed` - FastEmbed ONNX-based embeddings (lighter than sentence-transformers)
- `splade` - SPLADE sparse embeddings for hybrid search
    - `embed_sparse/2`, `embed_batch_sparse/2` for native sparse vectors
    - Automatic sparse-to-dense conversion for compatibility
- `colbert` - ColBERT multi-vector embeddings for fine-grained matching
    - `embed_multi/2`, `embed_batch_multi/2` for token-level vectors
    - `maxsim_score/2` for late interaction scoring
- `clip` - CLIP image/text cross-modal embeddings
    - `embed_image/2`, `embed_image_batch/2` for image embeddings
    - Text embeddings in same vector space for cross-modal search

#### Features

- Batch embedding with configurable chunk size
- Provider chain with automatic fallback on failure
- Application supervision tree with ETS-based rate limiting
- Comprehensive EUnit test suite

[0.2.0]: https://gitlab.enki.io/barrel-db/barrel-embed/-/releases/v0.2.0
[0.1.0]: https://gitlab.enki.io/barrel-db/barrel-embed/-/releases/v0.1.0
