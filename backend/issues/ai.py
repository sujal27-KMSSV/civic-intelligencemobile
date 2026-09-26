"""Graceful HTTP client for the FixMyGrid AI service.

Honesty contract: the AI service is OPTIONAL. When it is not configured or is
unreachable, the civic engine proceeds with rule-based analysis exactly as
before — this module NEVER raises, NEVER writes fake AI results, and NEVER
blocks a report submission beyond a short timeout.
"""

from __future__ import annotations

import json
import uuid
from urllib import request as urlrequest

from django.conf import settings


def ai_service_url() -> str:
    return (getattr(settings, "AI_SERVICE_URL", "") or "").strip()


def ai_timeout() -> float:
    try:
        return float(getattr(settings, "AI_SERVICE_TIMEOUT", 4))
    except (TypeError, ValueError):
        return 4.0


def _multipart(data: bytes, filename: str = "image.jpg", field: str = "file"):
    boundary = "----fixmygrid" + uuid.uuid4().hex
    head = (
        f"--{boundary}\r\n"
        f'Content-Disposition: form-data; name="{field}"; filename="{filename}"\r\n'
        "Content-Type: image/jpeg\r\n\r\n"
    ).encode()
    tail = f"\r\n--{boundary}--\r\n".encode()
    return head + data + tail, boundary


def _post(path: str, payload: bytes, content_type: str, timeout: float):
    url = ai_service_url().rstrip("/") + path
    req = urlrequest.Request(
        url, data=payload, headers={"Content-Type": content_type}, method="POST"
    )
    with urlrequest.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def image_analysis(image_name: str) -> dict | None:
    """POST the stored report photo to ``/v1/analyze-image``.

    Returns the parsed JSON payload, or ``None`` when the service is not
    configured, the image cannot be read, or any network / parse error occurs.
    """
    if not ai_service_url():
        return None
    from .civic import _read_saved_image  # local import (media/storage helper)

    data = _read_saved_image(image_name)
    if not data:
        return None
    try:
        body, boundary = _multipart(data, filename=image_name.rsplit("/", 1)[-1])
        return _post(
            "/v1/analyze-image",
            body,
            f"multipart/form-data; boundary={boundary}",
            ai_timeout(),
        )
    except Exception:
        return None


def priority_predict(
    *, severity: str, duplicate_count: int, age_hours: float, is_master: bool
) -> dict | None:
    """POST deterministic rule features to ``/v1/priority``.

    Returns the parsed ML prediction payload, or ``None`` on any failure
    (the rule-based priority remains authoritative when it is unavailable).
    """
    if not ai_service_url():
        return None
    try:
        body = json.dumps(
            {
                "severity": severity,
                "duplicate_count": duplicate_count,
                "age_hours": age_hours,
                "is_master": is_master,
            }
        ).encode("utf-8")
        return _post("/v1/priority", body, "application/json", ai_timeout())
    except Exception:
        return None