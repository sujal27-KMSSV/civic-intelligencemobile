# Computer vision (AI sidecar)

Endpoints: `POST /v1/analyze-image`, `POST /v1/classify`, `POST /v1/embed` —
FastAPI service under `ai_service/` (see `docs/fastapi.md`).

## Detection — YOLOv8n

- Weights: `yolov8n.pt` (Ultralytics v8.4.0 release), ~6.2 MB, COCO 80-class.
- Inference: Ultralytics engine, `conf=0.30`, `iou=0.45`, `device=cpu` (the
  sidecar is designed to run anywhere; CUDA is auto-detected if present).
- Output: `detections[]` = `{label, confidence, box:[x1,y1,x2,y2]}`.
- **Honesty:** labels are generic COCO nouns. Nothing in the product maps a
  detection to "is this a pothole". The service always emits a note to that
  effect into `vision.notes`.

## Classification — ResNet18

- Weights: `resnet18` from torchvision's ImageNet-pretrained set
  (`models.get_model_weights(config.CLASSIFIER_MODEL).DEFAULT`), top-5 labels.
- Output: `classifier_labels` (ordered) + full `top[]` with softmax scores.
- **Honesty:** ImageNet labels are everyday objects — the classifier is a
  coarse "what is photographed" cue for the dashboard, never authority.

## Preprocessing

- Images re-encoded to RGB, max dimension 1600 px, max payload 20 MB (server
  rejects larger with 400 before loading a model).
- `load_image` applies EXIF orientation (PIL `ImageOps.exif_transpose`).

## What is NOT here

- No custom training data, no fine-tuned damage detector, no auto-classify of
  status, no inference on the Django side (the engine only calls the sidecar;
  see `docs/ai.md` for the graceful-failure contract).

## Tests

`ai_service/tests/test_api.py` (9): real inference on CPU for embed/classify/
analyze + 503 and 400 error paths. Run: `cd ai_service && .\.venv\Scripts\python.exe -m pytest -q`.