"""Lazy, honest model registry.

Models are loaded on first use (never at import time) so request handlers can
report availability rather than crash when optional dependencies are missing.
Every model reports human-readable ``available`` + ``note`` state for /health.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from . import config

logger = logging.getLogger("fixmygrid.ai.registry")


class ModelUnavailable(RuntimeError):
    """Raised when a model cannot be loaded (missing dep, bad weights file)."""


@dataclass
class ModelRegistry:
    _encoder: object = field(default=None, init=False, repr=False)
    _encoder_name: str = field(default="", init=False)
    _yolo: object = field(default=None, init=False, repr=False)
    _yolo_name: str = field(default="", init=False)
    _classifier: object = field(default=None, init=False, repr=False)
    _classifier_name: str = field(default="", init=False)
    _priority: object = field(default=None, init=False, repr=False)
    _priority_name: str = field(default="", init=False)

    # ------------------------------------------------------------------
    # Torch image encoder (embeddings)
    # ------------------------------------------------------------------
    def encoder_available(self) -> bool:
        try:
            import torch  # noqa: F401
            import torchvision  # noqa: F401
        except Exception:
            return False
        return True

    def get_encoder(self):
        if self._encoder is None:
            if not self.encoder_available():
                raise ModelUnavailable(
                    "torch/torchvision not installed — image embeddings unavailable"
                )
            import torch
            import torch.nn as nn
            from torchvision import models

            name = config.EMBEDDING_MODEL
            try:
                model_fn = getattr(models, name)
                model = model_fn(weights="DEFAULT")
                model.eval()
                # Freeze: we only extract features, never fine-tune here.
                for param in model.parameters():
                    param.requires_grad = False
                trunk = getattr(model, "features", None)
                if trunk is None:
                    # Generic trunk = every child before the pooling/head layers.
                    trunk = torch.nn.Sequential(
                        *[m for m in model.children()][:-2]
                    )
            except Exception as exc:
                raise ModelUnavailable(f"could not load encoder '{name}': {exc}") from exc

            self._encoder = torch.nn.Sequential(trunk, torch.nn.AdaptiveAvgPool2d((1, 1))).eval()
            self._encoder_name = name
            logger.info("image encoder '%s' loaded", name)
        return self._encoder

    def encoder_name(self) -> str:
        if self._encoder is not None:
            return self._encoder_name
        return config.EMBEDDING_MODEL

    # ------------------------------------------------------------------
    # YOLO object detection (optional)
    # ------------------------------------------------------------------
    # ------------------------------------------------------------------
    # ImageNet classifier (generic content description)
    # ------------------------------------------------------------------
    def classifier_available(self) -> bool:
        try:
            import torch  # noqa: F401
            import torchvision  # noqa: F401
        except Exception:
            return False
        return True

    def get_classifier(self):
        if self._classifier is None:
            if not self.classifier_available():
                raise ModelUnavailable(
                    "torch/torchvision not installed — classification unavailable"
                )
            from torchvision import models

            name = config.CLASSIFIER_MODEL
            try:
                model = getattr(models, name)(weights="DEFAULT")
                model.eval()
            except Exception as exc:
                raise ModelUnavailable(f"could not load classifier '{name}': {exc}") from exc
            self._classifier = model
            self._classifier_name = name
            logger.info("classifier '%s' loaded", name)
        return self._classifier

    def classifier_name(self) -> str:
        if self._classifier is not None:
            return self._classifier_name
        return config.CLASSIFIER_MODEL

    # ------------------------------------------------------------------
    # YOLO object detection (optional)
    # ------------------------------------------------------------------
    def yolo_available(self) -> bool:
        if not config.YOLO_ENABLED:
            return False
        try:
            import ultralytics  # noqa: F401
        except Exception:
            return False
        return True

    def get_yolo(self):
        if self._yolo is None:
            if not self.yolo_available():
                raise ModelUnavailable(
                    "ultralytics not installed or YOLO disabled — detection unavailable"
                )
            from ultralytics import YOLO

            try:
                self._yolo = YOLO(config.YOLO_MODEL)
                self._yolo_name = config.YOLO_MODEL
            except Exception as exc:
                raise ModelUnavailable(f"could not load YOLO '{config.YOLO_MODEL}': {exc}") from exc
            logger.info("YOLO model '%s' loaded", config.YOLO_MODEL)
        return self._yolo

    def yolo_name(self) -> str:
        return self._yolo_name or config.YOLO_MODEL

    # ------------------------------------------------------------------
    # Priority model (scikit-learn GradientBoosting, joblib-serialized)
    # ------------------------------------------------------------------
    def priority_available(self) -> bool:
        try:
            import joblib  # noqa: F401
            from pathlib import Path

            return Path(config.PRIORITY_MODEL_FILE).is_file()
        except Exception:
            return False

    def get_priority(self):
        if self._priority is None:
            if not self.priority_available():
                raise ModelUnavailable(
                    f"priority model '{config.PRIORITY_MODEL_FILE}' not found"
                )
            import joblib

            try:
                self._priority = joblib.load(config.PRIORITY_MODEL_FILE)
                self._priority_name = "gradient-boosting-priority-v1"
            except Exception as exc:
                raise ModelUnavailable(f"could not load priority model: {exc}") from exc
            logger.info("priority model loaded from %s", config.PRIORITY_MODEL_FILE)
        return self._priority

    def priority_name(self) -> str:
        return self._priority_name or "gradient-boosting-priority-v1"

    # ------------------------------------------------------------------
    # Health snapshot
    # ------------------------------------------------------------------
    def health(self) -> dict:
        return {
            "embedding_encoder": {
                "available": self.encoder_available(),
                "name": self.encoder_name(),
                "note": "torchvision pretrained CNN — real feature embeddings",
            },
            "yolo": {
                "available": self.yolo_available(),
                "name": self.yolo_name(),
                "note": (
                    "COCO pretrained generic object detection — does NOT detect "
                    "civic categories"
                ),
            },
            "classifier": {
                "available": self.classifier_available(),
                "name": self.classifier_name(),
                "note": "ImageNet pretrained label description — generic content only",
            },
            "priority_model": {
                "available": self.priority_available(),
                "name": self.priority_name(),
                "note": "GradientBoosting trained to approximate the explainable rule policy",
            },
        }


registry = ModelRegistry()