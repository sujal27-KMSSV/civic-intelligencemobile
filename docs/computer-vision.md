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

### Custom FixMyGrid detector — evaluated 2026-09-26, deliberately NOT trained

A purpose-specific detector (pothole / garbage / damaged_road / broken_footpath
/ streetlight_damage / drainage_issue) was scoped and then **not** built. The
reason is data, not effort:

- the repository contains **one** real photograph (a single citizen upload) and
  **zero** YOLO/COCO annotation files;
- `ai_service/datasets/` does not exist;
- no permissively-licensed civic-defect dataset was available that could be
  used without uploading private citizen photographs to a third party.

Training on one unlabelled citizen image would produce a model that looks
trained and is worthless, so no dataset was fabricated and no training run is
claimed. The existing real pipeline is preserved unchanged.

**Why a custom model is still the right long-term answer.** Measured on the one
available road photograph, the COCO model returned `bird @ 0.39` and ImageNet
returned `iron / shovel / great_white_shark`. COCO simply has no civic classes.
This is exactly the gap a purpose-specific checkpoint would close.

**No redesign would be required.** `config.YOLO_MODEL` already reads the
`AI_YOLO_MODEL` environment variable, so a future checkpoint is supplied by
dropping in a `.pt` file and setting that variable — no code change:

```yaml
envVars:
  - key: AI_YOLO_MODEL   # e.g. /app/weights/fixmygrid_yolov8n.pt
    value: fixmygrid_yolov8n.pt
```

`registry.health()` and the `vision` payload would then report the new
checkpoint's name, and the honesty note in `routes.py` should be updated to
describe the custom class set at that time.

## Tests

`ai_service/tests/test_api.py` (11): real inference on CPU for embed/classify/
analyze, the priority endpoint, the priority band regression, the 503 and 400
error paths. Run: `cd ai_service && .\.venv\Scripts\python.exe -m pytest -q`.