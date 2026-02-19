"""barrel_embed - Embedding generation for Erlang.

Supports two backends:
- NIF backend (nif_api): Direct py:call integration via erlang_python
- Port backend (server): Async stdio-based communication (legacy)
"""

__version__ = "1.1.0"

# NIF backend API
from .nif_api import (
    load_model,
    embed,
    embed_sparse,
    embed_multi,
    embed_image,
    unload_model,
    loaded_models,
)

# Port backend (legacy)
from .server import AsyncEmbedServer

__all__ = [
    "__version__",
    # NIF API
    "load_model",
    "embed",
    "embed_sparse",
    "embed_multi",
    "embed_image",
    "unload_model",
    "loaded_models",
    # Port API (legacy)
    "AsyncEmbedServer",
]
