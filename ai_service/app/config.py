"""Configuration for the FixMyGrid AI service (env-driven, honest defaults)."""

from __future__ import annotations

import os
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
ARTIFACT_DIR = Path(os.getenv("AI_MODEL_DIR", str(BASE_DIR / "artifacts")))

PRIORITY_MODEL_FILE = os.getenv(
    "AI_PRIORITY_MODEL", str(ARTIFACT_DIR / "priority_model_v1.joblib")
)
PRIORITY_MODEL_META = os.getenv(
    "AI_PRIORITY_META", str(ARTIFACT_DIR / "priority_model_v1_meta.json")
)

# Image encoder (embeddings). "mobilenet_v3_small" pretrained via torchvision.
EMBEDDING_MODEL = os.getenv("AI_EMBEDDING_MODEL", "mobilenet_v3_small")
CLASSIFIER_MODEL = os.getenv("AI_CLASSIFIER_MODEL", "resnet18")
YOLO_MODEL = os.getenv("AI_YOLO_MODEL", "yolov8n.pt")
YOLO_ENABLED = os.getenv("AI_YOLO_ENABLED", "1").strip().lower() in ("1", "true", "yes", "on")

# Inference limits
MAX_IMAGE_BYTES = int(os.getenv("AI_MAX_IMAGE_BYTES", str(20 * 1024 * 1024)))
MAX_IMAGE_DIM = int(os.getenv("AI_MAX_IMAGE_DIM", str(1600)))

# Feature dimension of the configured embedding encoder (mobilenet_v3_small).
EMBEDDING_DIM = int(os.getenv("AI_EMBEDDING_DIM", "576"))