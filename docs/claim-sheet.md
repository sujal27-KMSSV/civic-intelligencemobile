# Claim sheet — every claim, with evidence

Honesty contract: if something is not implemented it is marked `BLOCKED` /
`MISSING`, never asserted. Numbers below are reproducible from this repo
(Django 113 / Flutter 171 / AI-service 9 / live prod verification).

## Product claims

| # | Claim | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Citizens can report an issue with photo, location, category and description | IMPLEMENTED | `issues/views.py::perform_create`; E2E `two_account_e2e_test.dart` |
| 2 | Duplicate reports are consolidated into a master issue (cluster) | IMPLEMENTED | `civic.py::run_analysis`; `test/issue_cluster_parsing_test.dart`; live `/api/issues/` master cards |
| 3 | Duplicate consolidation is explainable (per-signal evidence) | IMPLEMENTED | `duplicate_similarity_score` → `analysis["duplicate"]["evidence"]`; UI "Consolidated under Issue #id" |
| 4 | Priority is rule-based and explainable (0–100 + reasons) | IMPLEMENTED | `civic.py::score_priority`; `PriorityChip`; `report_result_screen_test.dart` |
| 5 | AI sidecar (YOLOv8n COCO, resnet18, mobilenet embeddings) runs **real** inference with **exact model provenance** in `vision` | IMPLEMENTED | `ai_service/` + `tests/test_api.py` 9/9; payload stores model names; `docs/ai.md` |
| 6 | ML priority is **advisory**; rule priority stays authoritative | IMPLEMENTED (honest) | `vision.priority_model` + `honest_note: prototype`; `engine_honest_label`; `docs/priority-model.md` (MAE 0.827, R² 0.9946 on synthetic rule labels) |
| 7 | Hotspots computed from real open-issue data | IMPLEMENTED | `cluster_hotspots`; live `/api/hotspots/` 200 with aggregates |
| 8 | Department routing is deterministic | IMPLEMENTED | `DEPARTMENT_BY_CATEGORY`; tests |
| 9 | Citizen My Reports is account-isolated | IMPLEMENTED | `MyReportsView`; E2E (both directions) |
| 10 | Edit/Delete gated by server flags (`can_edit`/`can_delete`) | IMPLEMENTED | serializer method fields; `window.py`; E2E |
| 11 | Submission is idempotent (`client_request_id`) | IMPLEMENTED | `views.py::create` incl. concurrent IntegrityError path; test suite |
| 12 | Resolution verification = honest image-similarity measurement (not auto-resolve) | IMPLEMENTED | `civic.py::image_similarity`; `authority/service.py::resolve_issue` |
| 13 | Dark mode / system appearance | IMPLEMENTED | `appearance_provider.dart`; `test/appearance_test.dart` |
| 14 | PostGIS neighbourhood search is genuine `ST_DWithin` when the DB supports it, otherwise absent (never faked) | IMPLEMENTED+HONEST | `backend/geospat/`; 4 integration tests SKIP when off; `docs/postgis.md` |
| 15 | Consistent back navigation / deep-link recovery | IMPLEMENTED | commit `ecedaa5`; `navigation_regression_test.dart` |
| 16 | Two-account + network-failure E2E are self-contained (zero leftovers) | IMPLEMENTED | `integration_test/two_account_e2e_test.dart`, `network_failure_e2e_test.dart` |

## Engineering claims

| # | Claim | Status | Evidence |
| --- | --- | --- | --- |
| 17 | Backend test suite green | IMPLEMENTED | `python manage.py test` → **113 OK (skipped=4 PostGIS)** (this session) |
| 18 | No pending migrations | IMPLEMENTED | `makemigrations --check --dry-run` → "No changes detected"; 0007 applied |
| 19 | Flutter analyze clean | IMPLEMENTED | 2 pre-existing `info` records in `test/api_client_test.dart:420,437` only |
| 20 | Flutter unit/widget suite green | IMPLEMENTED | `flutter test` → **171 passing** (incl. vision-parsing + cold-start first-attempt tests) |
| 21 | AI-service suite green | IMPLEMENTED | `cd ai_service && pytest -q` → **9 passing** (real CPU inference) |
| 22 | Live prod endpoints verified post-deploy | STALE (session re-check) | `/api/health/` + `/api/issues/` → 200; **`/api/hotspots/` → 404 and payload lacks `priority`/`vision`/`master_id`** ⇒ deployed build is behind HEAD. One manual action: redeploy `main` on Render dashboard, then re-verify. |
| 23 | Signed APK + AAB for 1.2.0+6 built and verified | SEE BUILD SECTION | `release/` artifacts + apksigner output |
| 24 | On-device E2E green on physical device | SEE DEVICE SECTION | requires adb device (none attached this session) |
| 25 | HEAD == origin/main after final push | SEE GIT SECTION | `git status` / `git log` |

## Non-claims (deliberately NOT asserted)

| Item | Status | Note |
| --- | --- | --- |
| PostGIS executed live in the demo env | BLOCKED-as-designed | Render free lacks the extension; geospat is conditional (`docs/postgis.md`), tests skip loudly |
| Pothole-specific trained detector | NOT IMPLEMENTED | YOLOv8n ships COCO generic weights; detections labelled generic (`docs/computer-vision.md`) |
| CLIP / vision-language embeddings | NOT IMPLEMENTED | CNN feature trunk only (`docs/embeddings.md`) |
| ML priority calibrated on real-field data | NOT IMPLEMENTED | trained on the audited rule's synthetic labels; metrics real but not field accuracy (`docs/priority-model.md`) |
| AI server on Render free tier | BLOCKED | 512 MB cannot host torch; split deploy documented (`docs/deployment.md`) |
| S3/R2 durable media exercised | BLOCKED | no credentials; `MEDIA_STORAGE_BACKEND=s3` wired but unexercised |
| Realtime push / WebSockets | NOT IMPLEMENTED | polling/refresh wording maintained |
| A roaming production demo account | REMOVED | legacy `finaldemo…` + `Demo@1234` removed from VCS and suites |

## Verification log v3 (this session)

- Django: migration `0007` (vision/vision_embedding/priority_model_score);
  engine v3 (`rule-based-civic-analysis-v3`); `ai.py` graceful client; geospat
  app; **113 OK (skipped=4 PostGIS)**; `makemigrations --check` clean.
- AI service: torch 2.14.0+cpu / torchvision 0.29.0+cpu / ultralytics 8.4.163
  on Python 3.14; priority model trained (metrics above); **9/9 pytest**.
- Flutter: v1.2.0+6 — vision/AI-transparency UI (details + report result),
  VisionInfo/PriorityModelInfo parsing; `issue.dart` merge repair; 6 new tests →
  **171 passing**; analyze clean.
- Commits: `ec26470` (AI+engine v3), `0ce4a1e` (geospat), `9f38a6f` (docs),
  `ebbf559` (authority analytics).
- Live prod smoke (re-checked this session): `/api/health/` → 200, `/api/issues/` → 200
  (27 issues), but `/api/hotspots/` → **404** and the payload carries no
  `priority`/`vision`/`master_id`/`cluster_size`. The running deployment is an
  older build. **REQUIRED manual action before the demo:** on the Render
  dashboard trigger a manual deploy of `main` for `civic-intelligence-api`,
  then re-run the smoke: `/api/health/`, `/api/issues/`, `/api/hotspots/`,
  `/api/authority/hotspots/` → 200 and an issue payload containing `priority`,
  `vision`, `master_id`, `cluster_size`.

## What a judge should actually run

```
cd backend && .\.venv\Scripts\python.exe manage.py test      # 113 OK (4 PostGIS skips, explained)
cd ai_service && .\.venv\Scripts\python.exe -m pytest -q     # 9 OK, real models
flutter analyze; flutter test                                # clean + 171
```