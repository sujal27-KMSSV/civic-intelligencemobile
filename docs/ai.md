# What "AI" means here — and what it does NOT

## The honest position (engine v3)

FixMyGrid now runs an **opt-in FastAPI AI sidecar** (`ai_service/`) with real,
pretrained models. When it is unreachable or unconfigured the civic engine is
**exactly the rule-based engine of v2** — nothing in the product breaks.

Crucially, every AI output is *labelled with its real provenance*. The app and
API never present a learned number as a ground truth; the rule-based priority
remains authoritative and the ML priority is stored as an **advisory**
`priority_model_score` under `vision.priority_model`.

| Capability | Model (real) | Honest UI/API label |
| --- | --- | --- |
| Image embedding | `mobilenet_v3_small` torchvision feature trunk, 576-dim L2-normalised | `embedding: {model: mobilenet_v3_small}` |
| Image classification | `resnet18` ImageNet pretrained, top-5 classes | `classifier: {model: resnet18}` |
| Object detection | `yolov8n` (Ultralytics) with the **COCO 80-class weights** | `detections[]` + note "COCO pretrained (generic labels)" |
| Learned priority | GradientBoostingRegressor trained on the audited rule's own synthetic scores | `vision.priority_model` + "prototype, advisory" note |

## Implemented signals (engine v3)

| Signal | Formula | Honest label in UI/API |
| --- | --- | --- |
| Duplicate GPS proximity | Haversine distance vs window, `1 - d/radius` | similarity evidence `gps` |
| Category match | exact equality | similarity evidence `category` |
| Text overlap | Jaccard on word tokens | similarity evidence `text` |
| Photo similarity | 64-bit dHash Hamming + brightness | similarity evidence `image` |
| Embedding cosine | L2-normalised `mobilenet_v3_small` embedding dot product | similarity evidence `embedding` |
| Severity | category base + keyword scan + duplicate uplift | `analysis.severity` |
| Priority (rule) | severity base + duplicates + recency + master uplift | `priority` + `reasons[]` |
| Priority (ML) | gradient boosting on {severity, duplicates, age, is_master} | `vision.priority_model` (advisory) |
| Hotspots | grid-bucket open issues (pure Python; PostGIS optional) | `/api/hotspots/` |
| Resolution | dHash + brightness of BEFORE/AFTER photos | `resolution_similarity` |
| Neighbourhood search | **PostGIS `ST_DWithin`** when `GEOSPAT_ENABLED=1` | `/api/geospat/nearby/` |

When embedding (`vision_embedding`) is absent for a report, the embedding
weight is dropped and the remaining duplicate weights are **renormalized**, so
a missing AI signal never silently lowers a similarity score.

## What is deliberately NOT claimed

- Detection of *potholes specifically*. `yolov8n.pt` ships the generic COCO
  80-class weights; detections are real but only identify generic objects
  (`car`, `person`, …). Auto-damage classification is **not** implemented.
- Our embeddings "understand" civic semantics. A CNN feature trunk measures
  photo-level visual similarity — **not** CLIP-style text/image semantics.
- A calibrated probability. The ML priority is a prototype trained on the
  audited rule's synthetic labels (real metrics, see `docs/priority-model.md`);
  the rule-based 0–100 stays authoritative for the priority chip.
- Predicted future outcomes or "96% accuracy" style numbers.
- Real-time push / WebSockets (polling/refresh only).
- That resolution verification auto-resolves issues — resolution stays an
  authority decision after an image-similarity measurement.

## Failure behaviour / honest degradation

- AI service unreachable, timed out, unconfigured, or `ModelUnavailable` →
  the engine proceeds **without** embedding/vision and renormalizes weights;
  HTTP is never blocked by the sidecar.
- GDAL/PostGIS absent → `geospat` app is not installed, the nearby route is
  not mounted, and its tests skip (`docs/postgis.md`).

## Forks / security notes

- The AI service listens on `ai_service/` and is meant to sit behind a
  private network edge (never exposed to public data, no auth in service
  itself — the Django app is the gatekeeper).
- torch CPU wheel ~180 MB; needs ~2 GB RAM at inference. Render's free
  tier (512 MB) **cannot** host it — documented deploy path targets the
  paid tiers or a dedicated box (`docs/deployment.md`).