# Image embeddings

`POST /v1/embed` → 576-dim float vector; used by the duplicate-intelligence
engine (v3) as the `embedding` similarity signal.

## Model

- `mobilenet_v3_small` **feature trunk** from torchvision (the network with the
  classifier head removed), then `AdaptiveAvgPool2d(1)` → 576-dim, L2-normalised.
- Cosine similarity is the plain dot product of the normalised vectors
  (`civic.embedding_cosine`), rounded to 4 dp.

## Honest boundaries

- The model is **not** CLIP and has no text/semantic space: identical-room
  scenes (e.g. two dashcam frames of the same pothole) get high cosine; two
  different potholes at the same block will score by visual similarity only.
- It is a real, measurable similarity — but the evidence line in the UI says
  exactly `embedding` (model `mobilenet_v3_small`) so it can be audited.
- If the AI service is down the signal is dropped and remaining duplicate
  weights are renormalized (never silently reduced).

## Storage

- Backend stores the vector on the `Issue` row (`vision_embedding` JSON, only
  set while the sidecar is healthy); pairwise cosine is computed in `civic.py`
  when both reports carry embeddings. The medium-term refinement is a
  pgvector index — explicitly out of scope for this prototype.

## Failure model

Refer to `docs/ai.md` — any sidecar failure returns `None` to the engine, which
proceeds with the rule-based path.