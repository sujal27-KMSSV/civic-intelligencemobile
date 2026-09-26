"""Generic image classification via torchvision (ImageNet 1000 classes).

Honesty contract: labels describe *generic* visual content (e.g. "street
sign", "traffic light", "garbage truck"). They are NOT civic-category
detection; the citizen's chosen category remains authoritative.
"""

from __future__ import annotations

from PIL import Image

from .. import config
from ..model_registry import ModelUnavailable, registry

CLASSIFY_TARGET = (224, 224)


def _preprocess(im: Image.Image) -> "object":
    import numpy as np
    import torch

    MEAN = (0.485, 0.456, 0.406)
    STD = (0.229, 0.224, 0.225)
    arr = np.asarray(im.resize(CLASSIFY_TARGET, Image.BILINEAR), dtype=np.float32)
    arr = (arr / 255.0 - np.asarray(MEAN, dtype=np.float32)) / np.asarray(
        STD, dtype=np.float32
    )
    arr = np.transpose(arr, (2, 0, 1))[None, ...]
    return torch.from_numpy(arr)


def classify(im: Image.Image, top_k: int = 5) -> tuple[list[dict], list[str]]:
    try:
        import torch
        from torchvision import models
    except ImportError as exc:
        raise ModelUnavailable("torch/torchvision not installed") from exc

    model = registry.get_classifier()
    with torch.inference_mode():
        logits = model(_preprocess(im))
        probs = torch.softmax(logits[0], dim=0)
        top = torch.topk(probs, min(top_k, probs.numel()))
    weights_enum = models.get_model_weights(config.CLASSIFIER_MODEL)
    labels = weights_enum.DEFAULT.meta["categories"]
    rows = [
        {"label": labels[int(i)], "score": round(float(s), 4)}
        for s, i in zip(top.values, top.indices)
    ]
    return rows, labels