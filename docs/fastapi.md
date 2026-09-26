# FastAPI AI sidecar (`ai_service/`)

A self-contained FastAPI micro-service that Django calls for image embeddings,
classifications, detections and an advisory priority prediction. It degrades
away to nothing: Django keeps working rule-based if this service is absent.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/health` | model registry + uptime, 200/503 |
| POST | `/v1/embed` | 576-dim L2-normalised `mobilenet_v3_small` embedding (multipart image) |
| POST | `/v1/classify` | resnet18 ImageNet top-5 (multipart image) |
| POST | `/v1/analyze-image` | embed + classify + detect (YOLOv8n COCO), one call |
| POST | `/v1/priority` | advisory GradientBoosting priority (JSON: severity_code, duplicate_count, age_hours, is_master) |

All models load lazily (a cold `/health` is fast); `ModelUnavailable` → 503.
Bad/oversized images → 400 before any model load.

## Run (local, CPU)

```
cd ai_service
.\.venv\Scripts\python.exe -m uvicorn app.main:app --port 8010
.\.venv\Scripts\python.exe -m pytest -q          # 9 tests, real inference
```

Requirements split: `requirements.txt` (CUDA-capable default) vs
`requirements-cpu.txt` (CPU wheels from the pytorch cpu index) — used on this
machine; see `docs/deployment.md`.

## Config (env)

| Var | Default | Meaning |
| --- | --- | --- |
| `AI_MODEL_DIR` | `ai_service/artifacts` | joblib + meta location |

Django side: `AI_SERVICE_URL=http://127.0.0.1:8010` (empty = rule-based only),
`AI_SERVICE_TIMEOUT` (default 4 s).

## Ownership boundary

- The AI service has **no auth and no business rules** — it accepts media and
  returns model outputs; it must sit behind the Django app / an internal
  network edge, never exposed publicly.
- Django is the gatekeeper (authentication, throttling, storage, merge logic).
- Additive label clarity: every response the engine stores carries the exact
  model name (`mobilenet_v3_small`, `resnet18`, `yolov8n`) so nothing can be
  mistaken for magic.