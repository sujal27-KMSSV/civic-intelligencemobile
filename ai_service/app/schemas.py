"""Pydantic response schemas for the AI service."""

from __future__ import annotations

from pydantic import BaseModel, Field


class ModelState(BaseModel):
    available: bool
    name: str | None = None
    note: str = ""


class HealthResponse(BaseModel):
    service: str = "fixmygrid-ai"
    status: str = "ok"
    models: dict[str, ModelState]


class EmbeddingResponse(BaseModel):
    model: str
    dim: int
    values: list[float]
    l2_norm: float


class Detection(BaseModel):
    label: str
    confidence: float
    box: list[float]  # [x, y, w, h] in pixels (normalized source image space)


class ClassLabel(BaseModel):
    label: str
    score: float


class ClassifyResponse(BaseModel):
    model: str
    top: list[ClassLabel]
    note: str = ""


class AnalyzeResponse(BaseModel):
    image: dict
    embedding: EmbeddingResponse
    detections: list[Detection] = Field(default_factory=list)
    classifier: ClassifyResponse | None = None
    notes: list[str]


class PriorityRequest(BaseModel):
    severity: str  # low | medium | high | critical
    duplicate_count: int = 1
    age_hours: float = 0.0
    is_master: bool = False


class PriorityResponse(BaseModel):
    model: str
    score: float  # 0..100 (model prediction)
    label: str
    explanation: dict  # feature contributions
    honest_note: str


class ErrorResponse(BaseModel):
    detail: str
    status: str = "error"