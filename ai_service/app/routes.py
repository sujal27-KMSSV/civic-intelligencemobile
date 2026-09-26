"""HTTP routes for the AI service."""

from __future__ import annotations

from fastapi import APIRouter, File, HTTPException, UploadFile

from .model_registry import ModelUnavailable, registry
from .schemas import (
    AnalyzeResponse,
    ClassifyResponse,
    ClassLabel,
    Detection,
    EmbeddingResponse,
    ErrorResponse,
    HealthResponse,
    PriorityRequest,
    PriorityResponse,
)
from .services import classification, detection, embeddings, priority, vision

router = APIRouter()


def _unavailable(exc: ModelUnavailable) -> HTTPException:
    return HTTPException(status_code=503, detail=str(exc))


@router.get("/health", response_model=HealthResponse)
def health() -> HealthResponse:
    return HealthResponse(models=registry.health())


@router.post(
    "/v1/embed",
    response_model=EmbeddingResponse,
    responses={400: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
)
async def embed(file: UploadFile = File(...)) -> EmbeddingResponse:
    data = await file.read()
    try:
        im = vision.load_image(data)
        vec, norm = embeddings.embed(im)
    except vision.ImageTooLarge as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except (ValueError, ModelUnavailable) as exc:
        raise _unavailable(exc) if isinstance(exc, ModelUnavailable) else HTTPException(
            status_code=400, detail=str(exc)
        )
    return EmbeddingResponse(
        model=registry.encoder_name(), dim=len(vec), values=vec, l2_norm=norm
    )


@router.post(
    "/v1/classify",
    response_model=ClassifyResponse,
    responses={400: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
)
async def classify(file: UploadFile = File(...)) -> ClassifyResponse:
    data = await file.read()
    try:
        im = vision.load_image(data)
        rows, _ = classification.classify(im)
    except vision.ImageTooLarge as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except (ValueError, ModelUnavailable) as exc:
        raise _unavailable(exc) if isinstance(exc, ModelUnavailable) else HTTPException(
            status_code=400, detail=str(exc)
        )
    return ClassifyResponse(
        model=registry.classifier_name(),
        top=[ClassLabel(**r) for r in rows],
        note="ImageNet pretrained labels — generic visual content, not civic-category detection",
    )


@router.post(
    "/v1/analyze-image",
    response_model=AnalyzeResponse,
    responses={400: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
)
async def analyze_image(file: UploadFile = File(...)) -> AnalyzeResponse:
    data = await file.read()
    try:
        im = vision.load_image(data)
    except vision.ImageTooLarge as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))

    notes: list[str] = []
    try:
        vec, norm = embeddings.embed(im)
    except ModelUnavailable as exc:
        raise _unavailable(exc)

    detections: list[Detection] = []
    if registry.yolo_available():
        try:
            detections = [Detection(**d) for d in detection.detect(im)]
            notes.append(
                "YOLO detection uses COCO pretrained labels (generic objects only)."
            )
        except ModelUnavailable as exc:
            notes.append(f"YOLO unavailable: {exc}")
    else:
        notes.append("YOLO detection not available (ultralytics not installed).")

    classifier_row: ClassifyResponse | None = None
    try:
        rows, _ = classification.classify(im)
        classifier_row = ClassifyResponse(
            model=registry.classifier_name(),
            top=[ClassLabel(**r) for r in rows],
            note="ImageNet pretrained labels — generic visual content, not civic-category detection",
        )
    except ModelUnavailable as exc:
        notes.append(f"classifier unavailable: {exc}")

    return AnalyzeResponse(
        image=vision.describe(im),
        embedding=EmbeddingResponse(
            model=registry.encoder_name(), dim=len(vec), values=vec, l2_norm=norm
        ),
        detections=detections,
        classifier=classifier_row,
        notes=notes,
    )


@router.post(
    "/v1/priority",
    response_model=PriorityResponse,
    responses={503: {"model": ErrorResponse}},
)
def priority_route(req: PriorityRequest) -> PriorityResponse:
    try:
        result = priority.predict(
            severity=req.severity,
            duplicate_count=req.duplicate_count,
            age_hours=req.age_hours,
            is_master=req.is_master,
        )
    except ModelUnavailable as exc:
        raise _unavailable(exc)
    return PriorityResponse(**result)