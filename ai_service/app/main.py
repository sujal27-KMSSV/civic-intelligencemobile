"""FixMyGrid AI service entrypoint.

Run locally:  uvicorn app.main:app --host 0.0.0.0 --port 8010
"""

from __future__ import annotations

from fastapi import FastAPI

from . import __version__
from .model_registry import registry
from .routes import router

app = FastAPI(
    title="FixMyGrid AI Service",
    version=__version__,
    description=(
        "Real computer-vision and machine-learning service for FixMyGrid: "
        "image embeddings, generic classification, YOLO detection and a "
        "prototype priority model. Every response states exactly which model "
        "produced it; no claims are made beyond what the models can do."
    ),
)

app.include_router(router)


@app.get("/")
def root() -> dict:
    return {"service": "fixmygrid-ai", "version": __version__, "docs": "/docs"}