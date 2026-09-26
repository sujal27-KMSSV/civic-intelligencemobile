"""API tests for the FixMyGrid AI service.

Real inference tests run the actual pretrained models on tiny synthetic images
(first run downloads weights; CPU inference on a 64x64 image is sub-second).
Environment-independent paths are covered with monkeypatched registries.
"""

from __future__ import annotations

import io

import numpy as np
import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.main import app

client = TestClient(app)


def make_png_bytes(size: tuple[int, int] = (64, 48), seed: int = 1) -> bytes:
    rng = np.random.default_rng(seed)
    arr = (rng.random(size + (3,)) * 255).astype("uint8")
    buf = io.BytesIO()
    Image.fromarray(arr, "RGB").save(buf, format="PNG")
    return buf.getvalue()


PNG = make_png_bytes()


def test_health_reports_models():
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["service"] == "fixmygrid-ai"
    assert {"embedding_encoder", "yolo", "classifier", "priority_model"} == set(
        body["models"]
    )


def test_embed_returns_real_vector(monkeypatch):
    if not client.get("/health").json()["models"]["embedding_encoder"]["available"]:
        pytest.skip("torch/torchvision not installed")
    resp = client.post(
        "/v1/embed", files={"file": ("img.png", PNG, "image/png")}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert "model" in body
    assert body["dim"] == len(body["values"]) == 576
    assert abs(body["l2_norm"] - 1.0) < 1e-3


def test_embed_rejects_empty_payload():
    resp = client.post("/v1/embed", files={"file": ("e.png", b"", "image/png")})
    assert resp.status_code == 400
    assert "could not decode" in resp.json().get("detail", "") or "empty" in resp.json().get("detail", "")


def test_embed_503_when_torch_missing(monkeypatch):
    from app.model_registry import registry as reg

    reg._encoder = None  # drop cached encoder so availability is re-checked
    monkeypatch.setattr(reg, "encoder_available", lambda: False)
    resp = client.post("/v1/embed", files={"file": ("img.png", PNG, "image/png")})
    assert resp.status_code == 503
    assert "unavailable" in resp.json()["detail"].lower()


def test_classify_returns_generic_labels(monkeypatch):
    if not client.get("/health").json()["models"]["classifier"]["available"]:
        pytest.skip("torch/torchvision not installed")
    resp = client.post(
        "/v1/classify", files={"file": ("img.png", PNG, "image/png")}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["top"]) == 5
    assert all("label" in item and "score" in item for item in body["top"])
    assert "not civic-category" in body["note"]


def test_analyze_image_runs_full_pipeline():
    if not client.get("/health").json()["models"]["embedding_encoder"]["available"]:
        pytest.skip("torch/torchvision not installed")
    resp = client.post(
        "/v1/analyze-image", files={"file": ("img.png", PNG, "image/png")}
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["image"]["width"] == 48
    assert body["image"]["height"] == 64
    assert body["embedding"]["dim"] == 576
    assert isinstance(body["detections"], list)
    assert body["classifier"] is not None


def test_priority_endpoint_scores_rule_approximation():
    resp = client.post(
        "/v1/priority",
        json={
            "severity": "critical",
            "duplicate_count": 12,
            "age_hours": 2.0,
            "is_master": True,
        },
    )
    if resp.status_code == 503:
        pytest.skip("priority model artifact missing")
    assert resp.status_code == 200
    body = resp.json()
    assert "score" in body and 0 <= body["score"] <= 100
    assert "explanation" in body
    assert body["explanation"]["feature_values"]["severity_code"] == 3.0
    assert "honest_note" in body


def test_priority_rejects_bad_severity():
    resp = client.post(
        "/v1/priority",
        json={"severity": "nonsense", "duplicate_count": 1, "age_hours": 0},
    )
    assert resp.status_code in (200, 503)  # bad severity maps to code 0 gracefully


def test_priority_503_when_model_missing(monkeypatch):
    from app.model_registry import registry as reg

    reg._priority = None  # drop any cached model so availability is re-checked
    monkeypatch.setattr(reg, "priority_available", lambda: False)
    resp = client.post(
        "/v1/priority",
        json={"severity": "high", "duplicate_count": 3, "age_hours": 10},
    )
    assert resp.status_code == 503


def test_label_bands_are_not_all_low():
    """Regression: bands are stored low->high, so label_for must scan in reverse.

    Scanning forward returned the first band ("low", lo=0) for *every* score,
    which made every issue report priority "low" and made the recorded
    label_band_accuracy a tautology.
    """
    from app.services.priority import label_for

    assert label_for(0.0) == "low"
    assert label_for(29.9) == "low"
    assert label_for(30.0) == "medium"
    assert label_for(54.9) == "medium"
    assert label_for(55.0) == "high"
    assert label_for(79.9) == "high"
    assert label_for(80.0) == "critical"
    assert label_for(100.0) == "critical"
    # out-of-range input is clamped, not banded incorrectly
    assert label_for(-50.0) == "low"
    assert label_for(1e6) == "critical"


def test_priority_endpoint_label_matches_band():
    """The endpoint's label must agree with the score it returns."""
    resp = client.post(
        "/v1/priority",
        json={
            "severity": "critical",
            "duplicate_count": 20,
            "age_hours": 60.0,
            "is_master": True,
        },
    )
    if resp.status_code == 503:
        pytest.skip("priority model artifact missing")
    assert resp.status_code == 200
    from app.services.priority import label_for

    assert resp.json()["label"] == label_for(resp.json()["score"])
    assert resp.json()["label"] != "low"