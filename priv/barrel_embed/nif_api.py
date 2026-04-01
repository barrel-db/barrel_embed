"""API for erlang_python py:call integration.

This module provides a simplified API for embedding generation that can be
called directly from Erlang via py:call. Models are cached in module-level
dictionaries for efficient reuse.
"""

import logging
import threading
from typing import Dict, List, Any, Optional, Tuple

logger = logging.getLogger(__name__)

# Thread-local model cache - each executor thread gets its own model instances
# This prevents segfaults from numpy/torch thread-local state corruption when
# models are loaded on one thread but used from another
_thread_local = threading.local()


def _get_thread_models():
    """Get the models dict for the current thread."""
    if not hasattr(_thread_local, 'models'):
        _thread_local.models = {}
    return _thread_local.models


def _get_model(provider: str, model_name: str):
    """Thread-local model loading - each thread gets its own instance."""
    models = _get_thread_models()
    key = (provider, model_name)
    if key not in models:
        models[key] = _load_model(provider, model_name)
    return models[key]


def _load_model(provider: str, model_name: str):
    """Load model based on provider type."""
    if provider == "sentence_transformers":
        from sentence_transformers import SentenceTransformer
        logger.info(f"Loading sentence-transformers model: {model_name}")
        return SentenceTransformer(model_name)

    elif provider == "fastembed":
        from fastembed import TextEmbedding
        logger.info(f"Loading FastEmbed model: {model_name}")
        return TextEmbedding(model_name=model_name)

    elif provider == "splade":
        import torch
        from transformers import AutoModelForMaskedLM, AutoTokenizer
        logger.info(f"Loading SPLADE model: {model_name}")
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModelForMaskedLM.from_pretrained(model_name)
        model.eval()
        return {"tokenizer": tokenizer, "model": model}

    elif provider == "colbert":
        import torch
        from transformers import AutoModel, AutoTokenizer
        logger.info(f"Loading ColBERT model: {model_name}")
        tokenizer = AutoTokenizer.from_pretrained(model_name)
        model = AutoModel.from_pretrained(model_name)
        model.eval()

        # ColBERT typically projects to 128 dimensions
        hidden_size = model.config.hidden_size
        linear = None
        dimension = 128

        if hasattr(model, 'linear'):
            linear = model.linear
            dimension = linear.out_features
        elif hidden_size != dimension:
            linear = torch.nn.Linear(hidden_size, dimension, bias=False)
            torch.nn.init.xavier_uniform_(linear.weight)

        return {"tokenizer": tokenizer, "model": model, "linear": linear, "dimension": dimension}

    elif provider == "clip":
        import torch
        from transformers import CLIPModel, CLIPProcessor
        logger.info(f"Loading CLIP model: {model_name}")
        processor = CLIPProcessor.from_pretrained(model_name)
        model = CLIPModel.from_pretrained(model_name)
        model.eval()
        return {"processor": processor, "model": model}

    raise ValueError(f"Unknown provider: {provider}")


def load_model(provider: str, model_name: str) -> dict:
    """Load model and return info.

    Args:
        provider: Provider type (sentence_transformers, fastembed, splade, colbert, clip)
        model_name: Model name/path

    Returns:
        dict with model info (dimensions, model, backend, etc.)
    """
    model = _get_model(provider, model_name)

    if provider == "sentence_transformers":
        return {
            "dimensions": model.get_sentence_embedding_dimension(),
            "model": model_name,
            "backend": provider
        }

    elif provider == "fastembed":
        # Get dimension by embedding a test string
        test_embedding = list(model.embed(["test"]))[0]
        return {
            "dimensions": len(test_embedding),
            "model": model_name,
            "backend": provider
        }

    elif provider == "splade":
        return {
            "vocab_size": model["tokenizer"].vocab_size,
            "model": model_name,
            "backend": provider,
            "type": "sparse"
        }

    elif provider == "colbert":
        return {
            "dimensions": model["dimension"],
            "model": model_name,
            "backend": provider,
            "type": "multi_vector"
        }

    elif provider == "clip":
        return {
            "dimensions": model["model"].config.projection_dim,
            "model": model_name,
            "backend": provider,
            "type": "image"
        }

    return {"model": model_name, "backend": provider}


def embed(provider: str, model_name: str, texts: list) -> list:
    """Generate embeddings for texts.

    Args:
        provider: Provider type
        model_name: Model name
        texts: List of text strings

    Returns:
        List of embedding vectors (list of floats)
    """
    if not texts:
        return []

    model = _get_model(provider, model_name)

    if provider == "sentence_transformers":
        embeddings = model.encode(texts, normalize_embeddings=True, show_progress_bar=False)
        return embeddings.tolist()

    elif provider == "fastembed":
        embeddings = list(model.embed(texts))
        return [e.tolist() for e in embeddings]

    elif provider == "clip":
        import torch
        results = []
        for text in texts:
            inputs = model["processor"](
                text=text, return_tensors="pt", padding=True, truncation=True
            )
            with torch.no_grad():
                text_features = model["model"].get_text_features(**inputs)
                text_features = text_features / text_features.norm(p=2, dim=-1, keepdim=True)
            results.append(text_features[0].tolist())
        return results

    raise ValueError(f"Provider {provider} does not support dense embedding")


def embed_sparse(provider: str, model_name: str, texts: list) -> list:
    """Generate sparse embeddings (SPLADE).

    Args:
        provider: Provider type (should be "splade")
        model_name: Model name
        texts: List of text strings

    Returns:
        List of sparse vectors: [{"indices": [...], "values": [...]}, ...]
    """
    if not texts:
        return []

    if provider != "splade":
        raise ValueError(f"Provider {provider} does not support sparse embedding")

    import torch
    model_data = _get_model(provider, model_name)
    tokenizer = model_data["tokenizer"]
    model = model_data["model"]

    # Tokenize
    inputs = tokenizer(
        texts,
        padding=True,
        truncation=True,
        max_length=512,
        return_tensors="pt"
    )

    # Get model output
    with torch.no_grad():
        output = model(**inputs)

    # SPLADE: log(1 + ReLU(logits)) * attention_mask, then max pool
    logits = output.logits
    relu_log = torch.log1p(torch.relu(logits))

    # Apply attention mask
    attention_mask = inputs["attention_mask"].unsqueeze(-1)
    weighted = relu_log * attention_mask

    # Max pooling over sequence length
    sparse_vecs, _ = torch.max(weighted, dim=1)

    # Convert to sparse format (indices and values)
    results = []
    for vec in sparse_vecs:
        # Get non-zero indices and values
        non_zero_mask = vec > 0
        indices = torch.where(non_zero_mask)[0].tolist()
        values = vec[non_zero_mask].tolist()
        results.append({"indices": indices, "values": values})

    return results


def embed_multi(provider: str, model_name: str, texts: list) -> list:
    """Generate multi-vector embeddings (ColBERT).

    Args:
        provider: Provider type (should be "colbert")
        model_name: Model name
        texts: List of text strings

    Returns:
        List of multi-vectors: [[[float, ...], ...], ...]
    """
    if not texts:
        return []

    if provider != "colbert":
        raise ValueError(f"Provider {provider} does not support multi-vector embedding")

    import torch
    import torch.nn.functional as F
    model_data = _get_model(provider, model_name)
    tokenizer = model_data["tokenizer"]
    model = model_data["model"]
    linear = model_data["linear"]

    results = []
    for text in texts:
        # Tokenize single text
        inputs = tokenizer(
            text,
            padding=True,
            truncation=True,
            max_length=512,
            return_tensors="pt"
        )

        # Get model output
        with torch.no_grad():
            output = model(**inputs)

        # Get token embeddings (last hidden state)
        token_embeddings = output.last_hidden_state[0]  # [seq_len, hidden_size]

        # Apply projection if needed
        if linear is not None:
            token_embeddings = linear(token_embeddings)

        # Normalize embeddings (ColBERT uses L2 normalization)
        token_embeddings = F.normalize(token_embeddings, p=2, dim=-1)

        # Get attention mask to filter padding tokens
        attention_mask = inputs["attention_mask"][0]

        # Filter out padding tokens
        valid_tokens = []
        for i, (emb, mask) in enumerate(zip(token_embeddings, attention_mask)):
            if mask == 1:  # Not padding
                valid_tokens.append(emb.tolist())

        results.append(valid_tokens)

    return results


def embed_image(model_name: str, images_base64: list) -> list:
    """Generate image embeddings (CLIP).

    Args:
        model_name: CLIP model name
        images_base64: List of base64-encoded images

    Returns:
        List of embedding vectors
    """
    if not images_base64:
        return []

    import base64
    from io import BytesIO
    import torch
    from PIL import Image

    model_data = _get_model("clip", model_name)
    processor = model_data["processor"]
    model = model_data["model"]

    results = []
    for image_data in images_base64:
        # Decode base64 image
        image_bytes = base64.b64decode(image_data)
        image = Image.open(BytesIO(image_bytes)).convert("RGB")

        # Process image
        inputs = processor(images=image, return_tensors="pt")

        # Get image embedding
        with torch.no_grad():
            image_features = model.get_image_features(**inputs)
            # Normalize
            image_features = image_features / image_features.norm(p=2, dim=-1, keepdim=True)

        results.append(image_features[0].tolist())

    return results


def unload_model(provider: str, model_name: str) -> bool:
    """Unload a model from current thread's cache to free memory.

    Args:
        provider: Provider type
        model_name: Model name

    Returns:
        True if model was unloaded, False if not found
    """
    models = _get_thread_models()
    key = (provider, model_name)
    if key in models:
        del models[key]
        return True
    return False


def loaded_models() -> list:
    """List all models loaded in current thread's cache.

    Returns:
        List of (provider, model_name) tuples
    """
    models = _get_thread_models()
    return list(models.keys())
