# What "AI" means here — and what it does NOT

## The honest position

This repository does **not** run a trained machine-learning model. There is no
YOLO, no OpenCV inference, no LLM, no ONNX runtime and no embedding server.
Marketing copy in earlier README versions described those as the stack — that
was inaccurate and has been corrected.

What ships is a **rule-based civic-intelligence engine** in
`backend/issues/civic.py`. Every number it writes is computed from explicit,
auditable rules and is reported to the user with that label:
"*Rule-based analysis (not a trained ML model)*", "*Similarity to existing
reports*", "*Explainable priority*".

## Implemented signals

| Signal | Formula | Honest label in UI/API |
| --- | --- | --- |
| Duplicate GPS proximity | Haversine distance vs 120 m window, `1 - d/radius` | similarity evidence `gps` |
| Category match | exact equality | similarity evidence `category` |
| Text overlap | Jaccard on word tokens of the description | similarity evidence `text` |
| Photo similarity | 64-bit difference-hash (dHash) Hamming distance | similarity evidence `image` |
| Severity | category base + keyword scan + duplicate uplift | `analysis.severity` |
| Priority | severity base + duplicate count + recency + master uplift | `priority` + `reasons[]` |
| Hotspots | grid-bucket real open issues, density + aggregates | `/api/hotspots/` |
| Resolution | dHash + brightness of BEFORE/AFTER photos | `resolution_similarity` |

## What is deliberately NOT claimed

- Visual detection of a pothole "in arbitrary imagery" (no object detector).
- A learned similarity metric (our score is a fixed weighted formula).
- Predicted future outcomes or "AI confidence" 96%–style numbers. The app
  shows the measured similarity to existing reports instead.
- Real-time push / WebSocket updates (pooling/refresh only).
- That resolution verification auto-resolves issues — it is an *image
  similarity measurement*; resolution stays an authority decision.

## Future (not part of v1.1.0)

A real CV/embedding pipeline would plug into `civic.py` **without** changing
the API shape or the mobile payload — the `Issue` columns and the flattened
serializer stay identical. Until then the phrase "Similarity to existing
reports" is what the UI shows, and this is intentional.