# FixMyGrid / Civic Intelligence — Session Dump

Self-contained technical summary of the project at `C:\dev\civic-intelligencemobile`
(verified against the actual source; nothing in this file is guessed).

**Version:** 1.2.0+6 (pubspec `version: 1.2.0+6`; `AppConstants.appVersion = '1.2.0'`).
**Package:** `com.civicintelligence.civic_intelligence`, versionCode 6.
**Git:** `main`, HEAD == origin/main == `b2cb9fe` (last release commit; see git history section).
**Production API:** `https://civic-intelligence-api.onrender.com` (live, contract verified).

---

# 1. Project Overview

FixMyGrid (Civic Intelligence) is a civic-intelligence platform that turns
citizen-reported urban problems (potholes, garbage, broken streetlights,
drainage) into structured, **de-duplicated**, **prioritized** and
department-routed actions for local authorities.

- **Problem:** identical issues get reported many times (noise for authorities);
  reports have no shared priority; nothing routes them to the right department;
  no evidence that a fix actually happened.
- **Core USP — duplicate intelligence:** a deterministic, explainable,
  rule-based engine (`backend/issues/civic.py`, "engine v3") consolidates
  duplicate reports into a single **master issue** with supporting reports,
  using five similarity signals (GPS distance, category match, text overlap,
  perceptual dHash image similarity, and — when the optional AI sidecar is up —
  CNN image embeddings). It outputs per-signal evidence and a hard 120 m GPS veto.
- **Honesty contract:** the "AI" is optional and always honestly labelled:
  YOLOv8n = generic COCO pretrained weights (not pothole-trained); embeddings =
  CNN (NOT CLIP); the ML priority model is an advisory prototype trained on
  synthetic/rule-derived labels. The rule-based engine is the authoritative,
  auditable source of truth.

## Complete workflow

```
Citizen (Flutter)
  │  photo + GPS + category + description (+ stable client_request_id)
  ▼
Django REST API  ──┐ (optional) ──► FastAPI AI/CV sidecar (torch; YOLOv8n,
  │ validate upload                                        ResNet18, CNN embeddings,
  │ save image + coordinates                               advisory priority)
  │ run civic engine: candidate prefilter → 120m GPS veto →
  │ per-signal similarity → master/supporting cluster →
  │ rule-based priority 0-100 (+ label, reasons) →
  │ severity → department routing → store analysis JSON
  ▼
PostgreSQL  (+ PostGIS if GEOSPAT_ENABLED=1; else pure-Python haversine fallback)
  │
  ▼
Authority web dashboard / staff REST API (IsAdminUser)
  │  list/triage → transition status (reported→verified→assigned→in_progress)
  │  → resolve with BEFORE/AFTER image evidence (honest dHash similarity)
  ▼
Citizen sees status, resolution state, master/cluster, priority + reasons,
  honest vision/AI transparency block on issue details.
```

---

# 2. System Architecture

```
Flutter Citizen App (lib/)
   │ HTTPS + DRF Token auth
   ▼
Django REST API (backend/) ──(optional AI_SERVICE_URL)──► FastAPI AI/CV (ai_service/)
   │
   ▼
PostgreSQL / PostGIS (backend/config/settings.py; PostGIS conditional)
   │
   ▼
Authority/Admin Frontend (backend/authority/ — staff API + Django templates)
```

Component responsibilities:

| Component | Responsibility |
| --- | --- |
| **Flutter app** (`lib/`) | Citizen UI: auth, feed/map of issues, reporting (photo/GPS/category/description), my-reports, issue details with duplicate/priority/vision transparency, profile/logout, dark mode. Riverpod state, go_router navigation, hardened HTTP client. |
| **Django REST API** (`backend/`) | Owns all business logic: auth (accounts), issue CRUD + idempotency (issues), duplicate engine + priority/department (issues/civic.py), lifecycle + resolution evidence (authority), optional PostGIS nearby search (geospat). Single source of truth. |
| **PostgreSQL** | Production DB (Render managed Postgres). SQLite fallback for local/dev. PostGIS is only enabled when the DB genuinely supports the extension (`GEOSPAT_ENABLED=1`); otherwise the geospat app/routes are absent, tests skip loudly, and civic.py uses bounding-box + haversine. Nothing is faked. |
| **FastAPI AI/CV sidecar** (`ai_service/`) | Optional, deployed separately (needs ~2 GB RAM, not free tier). Real inference: YOLOv8n COCO detections, ResNet18 classification, CNN embeddings, advisory GB-random-forest priority. Lazy model loading; 503 if a model is unavailable; degraded to "model unavailable" — never fabricated results. When `AI_SERVICE_URL` is unset or unreachable, the API is purely rule-based. |
| **Authority frontend** | `/authority/` Django template dashboard + `/api/authority/*` staff-only JSON API: triage, status transitions, resolution with before/after evidence, stats + hotspot heat-map cells. |

---

# 3. Frontend Architecture (Flutter)

**Stack:** Flutter + `flutter_riverpod` 2.6.1 + `go_router` 14.8.1 + `flutter_map`
6.2.1 (OSM tiles) + `http` + `flutter_secure_storage` + `geolocator`
11 + `geocoding` + `image_picker` + `latlong2`.

## Structure (`lib/`)

```
main.dart                      app bootstrap, providers, theme wiring
routing/app_router.dart        GoRouter: auth redirect, shell tabs, public /issue/:id
features/
  splash/ splash_screen.dart
  auth/    login_screen.dart, register_screen.dart, auth_repository.dart,
           auth_state.dart (Riverpod), auth_models.dart
  home/    home_screen.dart (feed)
  feed/    issue_feed_repository.dart
  map/     map_screen.dart
  issues/  issue_details_screen.dart (+provider), my_reports_screen.dart (+provider)
  reporting/ report_issue_screen.dart, report_review_screen.dart,
             report_result_screen.dart, report_draft.dart, report_draft_provider.dart,
             report_submission_provider.dart, report_repository.dart
  notifications/ notifications_screen.dart, notification_center.dart
  profile/ profile_screen.dart
core/
  network/ api_client.dart, auth_storage.dart
  constants/ api_constants.dart, app_constants.dart, colors.dart, severity_colors.dart
  errors/    app_exception.dart (Network/Server/Auth/Validation/Storage exceptions)
  theme/     app_theme.dart, appearance_provider.dart
  utils/     perf.dart
  widgets/   issue_card.dart, empty_state.dart, status_chip.dart, severity_chip.dart,
             priority_chip.dart, remote_photo.dart, report_edit_dialog.dart, app_logo.dart
models/      issue.dart, user.dart, location_point.dart
services/    media_service.dart, location_service.dart, notification_service.dart
```

## Major screens & flow

- **Splash → auth**: splash decides login vs shell via stored token. Login/Register
  call `ApiClient` (Token auth), session persisted via `SecureAuthStorage`
  (OS keystore/Keychain; defensive reads, 401 → auto-logout).
- **Shell (tabs)**: Home feed · Map · My Reports · Profile. Tabs use router
  `go()` — no stack growth; back arrow suppressed on tab roots.
- **Feed**: collapsed master issues; each card shows category, image, status,
  severity, **priority chip (0-100 + label)**, department, "Consolidated under
  Issue #id" for supporting duplicates.
- **Issue details** (`/issue/:id`, public for reads): full data, duplicate
  evidence/analysis, status timeline, resolution block, and the v1.2.0
  **vision/AI transparency** section: model names, classifier top-3, detections,
  advisory-ML priority + honest "not field-calibrated" note. Honest wording
  "similarity to existing reports", never "confidence" where it is not.
- **Report flow** (pushed): Photo (camera/gallery via `media_service`) →
  Location (GPS via `location_service`, geocoded address) → Review
  (`report_review_screen`) → Result (`report_result_screen`, shows duplicate
  consolidation + priority + AI transparency note). Draft persisted across
  steps in `report_draft_provider`. Submission regenerated client photo only.
- **My Reports**: account-isolated list, edit/delete gated by server flags
  `can_edit`/`can_delete` (10-minute retraction window).
- **Notifications**: in-app notification center fed by `notification_service`.
- **Profile**: account info, appearance toggle (dark/system/light), about/legal,
  logout.

## Navigation

- GoRouter with auth redirect: unauthenticated → `/login`; authenticated → shell.
  `/issue/:id` intentionally public (deep-linkable from shares).
- Pushed screens (issue details, notifications, report flow) get back
  affordances (`canPop`-aware leading arrows); report screens use `PopScope`
  to block accidental back-drops mid-submission and reset state on completion.
- Verified zero dead ends; deep-link recovery tested; Android back/back-gesture
  handled.

## API client (`core/network/api_client.dart`)

- Base URL: `ApiConstants.baseUrl` = `String.fromEnvironment('API_BASE_URL',
  defaultValue: 'https://civic-intelligence-api.onrender.com')` — any release
  build defaults to production HTTPS; local dev overrides with `--dart-define`.
- Auth header from secure storage (`Token <key>`); `onUnauthorized` → logout.
- JSON parsing off the UI isolate above 64 KB; `_handleIssueList`/`_handleResponse`
  normalize shapes.
- **Timeout/retry (cold-start aware)**: safe-to-retry ops (reads, auth,
  idempotent submissions) get a **60 s cold-start budget on the first attempt**
  and a single 1 s-backoff retry with the same budget — Render free containers
  sleep ~15 min idle and take ~30-60 s to boot. Non-retried paths (delete)
  use the 20 s default. `submitIssue` uses 120 s/60 s budgets and always sends a
  stable `client_request_id` so retries cannot duplicate reports.
- Error classification → `NetworkException` kinds (dns / timeout / connectionRefused
  / connectionReset / tls / noInternet / other) with retryable flags and
  user-facing messages. 401→`AuthException`, 400/422 field errors→
  `ValidationException`, else `ServerException`. **Never shows fake success
  after a failed mutation.**

## Dark mode / states

- `appearance_provider` (system default; manual override persisted) driving
  Material themes. Dark-mode contrast verified across screens.
- Every list/data screen implements loading / empty (`EmptyState`) / error
  (with retry) states; report submission has a persistent "Still working…"
  spinner that survives app-backgrounding, with duplicate-safe retry.

---

# 4. Backend Architecture (Django + DRF)

**Stack:** Django 6.1.1, djangorestframework 3.18.1, django-cors-headers 4.9.0,
Pillow 12.3.0, gunicorn 26.2.0, whitenoise 6.12.0, psycopg[binary] 3.3.5,
django-storages[boto3] 1.14.6 (optional S3), python-dotenv.

## Apps

| App | Purpose |
| --- | --- |
| `accounts` | Custom `User` (`AUTH_USER_MODEL`), register/login views + serializers, custom password complexity validator, `AuthRateThrottle` (default 10/min per IP for anonymous auth surface). Endpoints: `POST /api/auth/register/`, `POST /api/auth/login/` → DRF Token. |
| `issues` | `Issue` model; `IssueViewSet`; idempotent creation; civic engine (`civic.py`), AI client (`ai.py`), delete-window policy (`window.py`), image validators (`validators.py`), public hotspots. |
| `authority` | Staff-only dashboard + REST API (`api.py`, `service.py`): triage, transitions, resolution evidence, stats, hotspot cells. All `IsAdminUser`. |
| `geospat` | Conditional PostGIS app; mounted only when `POSTGRES_GIS_ENABLED` (`DB_ENGINE=postgresql` + `GEOSPAT_ENABLED=1`); real `ST_DWithin` nearby search + signal-sync command. Otherwise routes absent and tests skip. |
| `config` | Settings, root URLconf, WSGI/ASGI. |

## Models — `issues.Issue` (key fields)

`reporter` (FK), `image` (ImageField `issues/%Y/%m/%d/`), `client_request_id`,
`image_source`, `description`, `address`, `latitude`/`longitude` (Decimal 9,6),
`category`, `confidence`, `severity`, `duplicate` (bool), `duplicate_count`,
`duplicate_of` (FK self), `department`, `status`, `analysis` (JSON),
`priority`/`priority_label`/`priority_reasons`, `image_dhash`, `image_brightness`,
`vision` (JSON)/`vision_embedding` (JSON)/`priority_model_score` (migration 0007),
`resolution_image`, `resolution_notes`, `resolution_similarity`, `resolved_at`,
`created_at`/`updated_at`.

## Views / endpoints (`config/urls.py`)

- `GET /api/health/` — `{"status":"ok"}` (no DB).
- `POST /api/auth/register/`, `POST /api/auth/login/` (AllowAny + throttle).
- `/api/issues/` (`IssueViewSet`): list (collapsed to masters by default;
  `?collapse=0` → all), retrieve, create, update/patch/delete.
- `GET /api/my-reports/` — authenticated owner-only list.
- `GET /api/hotspots/` — public grid cells from real data.
- `/api/authority/*` — staff-only: `issues/`, `issues/<pk>/`, transitions,
  resolve (multipart image + notes), `stats/`, `hotspots/` heat-map cells.
- `POST /api/geospat/nearby/` — only when PostGIS enabled.

## Authentication / authorization

- DRF default `AllowAny`; auth classes: `TokenAuthentication` +
  `SessionAuthentication`.
- Issue list/detail: **read AllowAny** (public civic feed); **write
  IsAuthenticated**; edit/delete via `IsOwnerOrStaff` (reporter only, or staff).
  `REPORTER_EDITABLE_FIELDS` = description/address only; status/priority/
  department/resolution fields are authority-owned and cannot be written by
  reporters.
- Authority API: every view `IsAdminUser`; no anonymous data.
- Production (`DEBUG=False`) refuses to start without `SECRET_KEY`; secure
  cookies, optional HSTS, `SECURE_PROXY_SSL_HEADER`, `CSRF_TRUSTED_ORIGINS`
  env-driven, CORS locked to `CORS_ALLOWED_ORIGINS`.

## Issue lifecycle

`reported → verified → assigned → in_progress → resolved` (plus `rejected`).
`authority/service.py::transition_issue` validates allowed transitions;
`resolve_issue` requires a real BEFORE/AFTER image (multipart), computes honest
perceptual **dHash similarity** (`civic.py::image_similarity`), stores
`resolution_similarity`, and **cannot mark resolved without evidence**.

## Idempotency + concurrency

`POST /api/issues/` carries `client_request_id`; unique constraint on
(`reporter`, `client_request_id`); creation runs in `transaction.atomic` with
`select_for_update`; a retried/crashed submit returns the original issue (the
Flutter client sends the same id on retry). Deletes honor a 10-minute
retraction window (`window.py`) and re-analysis updates clusters concurrently.

## Duplicate intelligence (`issues/civic.py`, engine v3)

- Candidate prefilter: bounding box (≈±0.002°) over stored issues; then
  per-signal scores:
  - **GPS** (27% of score): distance-based, HAVERSINE in pure Python.
  - **category** (10%), **text** (20%) overlap, **image** (21%) via perceptual
    dHash similarity (cached), **embedding** (25%) via cosine similarity when
    the AI sidecar supplied embeddings (weights renormalized when absent; must
    sum to 1.0; overridable via `W_GPS/W_CATEGORY/W_TEXT/W_IMAGE/W_EMBEDDING`).
  - **Hard veto: `DUPLICATE_RADIUS_M = 120.0`** — beyond 120 m never duplicates.
- `run_analysis` sets master/supporting (`duplicate_of`, `is_master`,
  `master_id`, `cluster_size`, `cluster_member_ids`, `duplicate_count`) and
  stores per-signal `duplicate["evidence"]` — deterministic + explainable.
- **Priority:** `score_priority` → 0-100 + `priority_label` + `priority_reasons`
  (feature contributions), authoritative and auditable; severity + department
  routing via `DEPARTMENT_BY_CATEGORY`.
- **Hotspots:** `cluster_hotspots(qs, grid, limit)` gridded real-data
  aggregation (public and authority heat-map variants).
- **Optional AI sidecar** (`issues/ai.py`): posts stored photo to
  `/v1/analyze-image`; NEVER raises, NEVER fabricates; returns `None`-graceful
  (or rules-only) on any failure/timeout; honors `AI_SERVICE_TIMEOUT`.

## File / image handling

`validators.py`: ≤10 MB, PIL decode verify, min dimension 320 px, max ~24 MP.
Serializer `image` is write-only; server stores and serves via
`MEDIA_ROOT`/`MEDIA_URL` (Optionally `MEDIA_STORAGE_BACKEND=s3` with
`django-storages[boto3]`). Authority resolution images validated similarly.

## Settings highlights

- SQLite by default; `DB_ENGINE=postgresql` + `DB_*` → PostgreSQL; PostGIS only
  when genuinely available.
- Static via Whitenoise (`CompressedManifestStaticFilesStorage`).
- DRF throttle: `auth: 10/min` (anonymous login/register only).

---

# 5. AI / Computer-Vision Service (FastAPI sidecar)

**Stack:** Python 3.14, torch 2.14.0+cpu, torchvision 0.29.0+cpu, ultralytics
8.4.163, FastAPI. **Lives in `ai_service/`, deployed independently.**

- `app/main.py` app factory; `app/routes.py` endpoints; `app/config.py`
  (`AI_MODEL_DIR=/app/artifacts`); `app/model_registry.py` — lazy on first use,
  per-model `available` flags, **503 when a model is unavailable** (never fake
  results).
- `services/detection.py` — YOLOv8n with **pretrained COCO weights** (generic
  classes; explicitly NOT pothole-trained).
- `services/classification.py` — ResNet18 ImageNet classifier.
- `services/embeddings.py` — CNN feature trunk (mobilenet_v3_small), L2-normalized
  vector, **explicitly NOT CLIP, not vision-language**.
- `services/vision.py` — image decode/size limits before inference.
- `services/priority.py` — gradient-boosted trees over 4 features producing an
  **advisory priority**; `artifacts/priority_model_v1_meta.json` records the
  real (synthetic-eval) metrics: **MAE 0.827, RMSE 1.041, R² 0.9946, label
  band 1.0, n_train 6400 / n_test 1600**, with `honest_label` stating it is a
  prototype trained on the audited rule's own labels, not field-calibrated.
- `scripts/train_priority_model.py` regenerates those synthetic labels from the
  rule engine (seed 20260926).
- Health endpoint `/health`; Django consumes it only when `AI_SERVICE_URL` is set.

---

# 6. Deployment

- `render.yaml` blueprint: `civic-intelligence-api` (Docker, rootDir `backend`,
  free plan, `healthCheckPath /api/health/`) + optional `civic-intelligence-ai`
  (standard plan). `DB_*`, `SECRET_KEY(generateValue)`, `CORS_*`,
  `AI_SERVICE_URL`, `GEOSPAT_ENABLED=False` per comments.
- `backend/Dockerfile`: `python:3.14-slim`, `pip install -r requirements.txt`,
  CMD `python manage.py migrate --noinput && python manage.py collectstatic
  --noinput && gunicorn config.wsgi:application --bind 0.0.0.0:$PORT --workers 3
  --timeout 120`.
- **Production status (verified by live HTTP this session):**
  `/api/health/` 200 · `/api/issues/` 200 with current contract (`priority`,
  `priority_label`, `priority_reasons`, `vision`, `priority_model_score`,
  `master_id`, `is_master`, `cluster_size`, `cluster_member_ids`,
  `duplicate_of`) · `/api/hotspots/` 200 · `/api/authority/hotspots/` 401 for
  anonymous (admin authz; endpoint live) · citizen smoke flow passed
  (register→login→submit 201→retrieve→delete 204→404 clean).
- **AI sidecar: NOT deployed** on Render (free tier too small for torch). New
  submissions return `vision: {"status":"not_analyzed","service":null}` — the
  honest rule-based fallback.

---

# 7. Release artifacts (verified)

| Artifact | Path | SHA-256 |
| --- | --- | --- |
| Final APK | `release/FixMyGrid-FINAL.apk` (also copied to `Downloads`) | `ECF5FEE7D8BDD53FC229FAE24F1BA024C68C345D18E40B5A0E9268457B8148C5` |
| Final AAB | `release/FixMyGrid-FINAL.aab` | `C877B45347E15892ACB3296629F4D314B9690646B1B79A4350C0E3085C4451B4` |

package `com.civicintelligence.civic_intelligence`, versionName `1.2.0`,
versionCode `6`, signed (Signer #1 DN `CN=Civic Intelligence…`), INTERNET
permission, HTTPS-only (`usesCleartextTraffic=false`). Built with
`--dart-define=API_BASE_URL=https://civic-intelligence-api.onrender.com`.
Fallback `release/FixMyGrid-1.2.0.apk` remains untouched.

---

# 8. Verification baselines & git

- **Flutter tests:** 171/171 pass · `flutter analyze` clean (2 pre-existing
  `info`s only: `test/api_client_test.dart` line ~420/437 prefer_const_constructors).
- **Django tests:** 113 OK, **4 PostGIS tests skip** on non-GIS DB.
- **AI service tests:** 9/9 (real CPU inference).
- **Migrations:** `makemigrations --check --dry-run` → "No changes detected"
  (current DB schema at `issues/0007`).
- **Git history (main):** `9166951` v1.0.0 → `2ca10bb` rebrand/hardening →
  `d1febc7` edit/delete/idempotency hardening → `85bd3a6` v1.1.0 (duplicate v2,
  priority, dark mode) → `ec26470` AI sidecar + engine v3 → `0ce4a1e` geospat →
  `9f38a6f` docs/deploy → `ebbf559` authority analytics → `0860e32` v1.2.0+6
  (vision-transparency UI, issue model repair) → `e362bda` final-readiness
  (cold-start first attempt + docs) → **`b2cb9fe`** `fix: pin django-storages
  to released version` (1.15.0 → 1.14.6; the 1.15.0 pin did not exist on PyPI
  and broke the Render Docker build; this commit is currently deployed).

## Known, documented limitations

- Physical-device E2E: **UNVERIFIED** (no ADB device available).
- Live PostGIS verification: **UNVERIFIED** (Render free PostgreSQL has no
  PostGIS extension; conditional implementation exists, tests skip loudly).
- AI sidecar on Render: **NOT deployed** (free tier too small); rule-based
  fallback is production behavior.
- `/api/authority/hotspots/` response payload not staff-verified (no admin
  credentials); endpoint is live and correctly 401-gated for anonymous.
- S3/R2 media: wired (`MEDIA_STORAGE_BACKEND=s3`) but unexercised (no creds).
- Demo accounts: no roaming account; prior verification runs left only
  credential-free randomized throwaway user rows (no account-deletion endpoint);
  zero report records were left behind.