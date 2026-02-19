"""barrel_embed - Embedding generation for Erlang.

Uses erlang_python NIF for direct py:call integration.
"""

__version__ = "1.2.0"

from .nif_api import (
    load_model,
    embed,
    embed_sparse,
    embed_multi,
    embed_image,
    unload_model,
    loaded_models,
)

__all__ = [
    "__version__",
    "load_model",
    "embed",
    "embed_sparse",
    "embed_multi",
    "embed_image",
    "unload_model",
    "loaded_models",
]
