# System Architecture (v1.2.0)

This document describes the **actual** system, not an aspirational one. Every
component below exists in this repository and is covered by tests.

```text
  CITIZEN (Android app, Flutter)
     |
     | HTTPS multipart (photo) + JSON
     v
  Django REST Framework API  (backend/  — Render, Docker, gunicorn)
     |
     +-- issues/civic.py      rule-based civic intelligence engine
     |      (duplicate, severity, priority, hotspots, routing, resolution)
     |
     +-- issues/views.py      IssueViewSet, MyReports, hotspots, idempotency
     |
     +-- authority/            staff JSON endpoints + dashboard data
     |
     v
  PostgreSQL (managed, Render free tier; SQLite for local dev)
     |
     v
  Storage backend (local disk in dev/demo; S3/R2 via env var — see blocked)
```

## Components

### 1. Flutter mobile app (`lib/`)

- **Home / Community feed** — collapsed to one card per master issue
  (server-side `collapse=1`); each card shows the priority chip, the
  "Consolidates N reports" count and the "Consolidated under Issue #x" link for
  supporting reports.
- **Report flow** — camera/gallery photo, location capture, category,
  description; submission is idempotent via `client_request_id`.
- **My Reports** — account-isolated; Edit/Delete only when the server says
  `can_edit` / `can_delete`.
- **Map** — hotspot cells from `/api/hotspots/`.
- **Profile** — session, logout, appearance (System/Light/Dark, persisted).
- All user-facing intelligence labels are honest ("Similarity to existing
  reports", "Explainable priority").

### 2. Django REST API (`backend/`)

Flattened issue payloads on every read/write endpoint so the app never needs
to traverse nested serializers. `IssueSerializer` exposes:
`id, image_url, description, latitude, longitude, address, status, created_at,
updated_at, category, confidence (similarity), severity, duplicate,
duplicate_count, department, priority, priority_label, priority_reasons,
master_id, is_master, cluster_size, cluster_member_ids, resolution_status,
can_edit, can_delete, …`

### 3. Civic engine (`backend/issues/civic.py`)

Deterministic, rule-based, auditable — see [ai.md](ai.md) and
[duplicate-intelligence.md](duplicate-intelligence.md).

### 4. Authority JSON API + dashboard (`backend/authority/`, `authority-web/`)

Staff-only endpoints for issue list/detail (with cluster), lifecycle
transitions, resolution evidence upload (with honest image similarity), stats
and hotspot cells.

## Data model highlights

```text
Issue
  id, reporter -> User
  image (media), image_source, resolution_image, resolution_notes
  description, address, latitude, longitude
  category, severity (low/medium/high/critical), status (6 lifecycle states)
  duplicate (bool), duplicate_of -> Issue (cluster root), duplicate_count
  priority (0..100), priority_label, priority_reasons (JSON)
  confidence (0..1) == similarity to the matched cluster
  analysis (JSON: full engine breakdown incl. per-signal duplicate evidence)
  image_dhash, image_brightness   (cached perceptual features)
  resolution_similarity, resolved_at
  client_request_id   (unique per reporter — idempotency)
```

See `backend/issues/models.py`, `migrations/0006_*.py`.

## PostGIS and live ML — capability boundaries (honest)

- **PostGIS** ships as the conditional `geospat` app: genuinely installed
  (and `/api/geospat/nearby/` routed, tests un-skipped) only when the DB
  really exposes PostGIS (`DB_ENGINE=postgresql` + `GEOSPAT_ENABLED=1`).
  Otherwise spatial detection stays bounding-box + haversine + grid
  bucketing — never an emulated PostGIS. See [postgis.md](postgis.md).
- **AI inference** lives in the opt-in FastAPI sidecar (`ai_service/`), real
  pretrained models, gracious to absence. See [ai.md](ai.md),
  [computer-vision.md](computer-vision.md), [embeddings.md](embeddings.md).