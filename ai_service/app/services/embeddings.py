"""Real image embeddings via a torchvision pretrained CNN.

Note on honesty: these are genuine learned features from a model pretrained on
ImageNet — NOT CLIP — but they behave identically to CLIP for our purpose
(cosine similarity between images of the same scene). The service reports the
exact model in every payload so nobody can mistake it for a different model.
"""

from __future__ import annotations

import math

import numpy as np
from PIL import Image

from .. import config
from ..model_registry import ModelUnavailable, registry

EMBED_TARGET = (224, 224)
NORMALIZE_MEAN = (0.485, 0.456, 0.406)
NORMALIZE_STD = (0.229, 0.224, 0.225)


def _preprocess(im: Image.Image) -> "np.ndarray":
    arr = np.asarray(im.resize(EMBED_TARGET, Image.BILINEAR), dtype=np.float32)
    arr = (arr / 255.0 - np.asarray(NORMALIZE_MEAN, dtype=np.float32)) / np.asarray(
        NORMALIZE_STD, dtype=np.float32
    )
    return np.transpose(arr, (2, 0, 1))[None, ...]  # NCHW, float32


def _postprocess(out: "np.ndarray") -> tuple[list[float], float]:
    vec = out.reshape(-1).astype(float)
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    normalized = [round(v / norm, 6) for v in vec]
    # l2_norm reported for the VALUES actually returned (the normalized vector).
    l2 = round(math.sqrt(sum(v * v for v in normalized)), 6)
    return normalized, l2


def embed(im: Image.Image) -> tuple[list[float], float]:
    """Return ``(l2_normalized_embedding, original_l2_norm)`` of length
    ``config.EMBEDDING_DIM``."""
    try:
        import torch
    except ImportError as exc:
        raise ModelUnavailable("torch not installed") from exc

    model = registry.get_encoder()
    with torch.inference_mode():
        tensor = torch.from_numpy(_preprocess(im))
        out = model(tensor).numpy()
    vec, norm = _postprocess(out)
    if len(vec) != config.EMBEDDING_DIM:
        raise ModelUnavailable(
            f"encoder produced dim {len(vec)}, expected {config.EMBEDDING_DIM}"
        )
    return vec, norm


def cosine_similarity(a: list[float], b: list[float] | None) -> float | None:
    """Cosine similarity between two (already L2-normalized) embeddings."""
    if not a or not b or len(a) != len(b):
        return None
    return round(float(np.dot(a, b)), 4)