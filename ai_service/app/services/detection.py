"""YOLO object detection (ultralytics, COCO-pretrained).

Honesty contract: only COCO classes are detected. Potholes, streetlights,
garbage heaps etc. are NOT COCO classes, so a detection result is a *generic*
object description, never a civic-category verdict. The payload says so
explicitly.
"""

from __future__ import annotations

from PIL import Image

from ..model_registry import ModelUnavailable, registry


def detect(im: Image.Image) -> list[dict]:
    model = registry.get_yolo()
    results = model.predict(
        source=im, conf=0.30, iou=0.45, verbose=False, device="cpu"
    )
    if not results:
        return []
    result = results[0]
    boxes = result.boxes
    if boxes is None:
        return []
    out: list[dict] = []
    names = result.names
    for box, conf, cls in zip(boxes.xyxy, boxes.conf, boxes.cls):
        x1, y1, x2, y2 = (float(v) for v in box)
        out.append(
            {
                "label": names[int(cls)],
                "confidence": round(float(conf), 4),
                "box": [round(x1, 1), round(y1, 1), round(x2 - x1, 1), round(y2 - y1, 1)],
            }
        )
    return out