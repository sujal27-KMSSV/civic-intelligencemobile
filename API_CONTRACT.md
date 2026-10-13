# Civic Intelligence — Flutter ↔ Backend API Contract

This is the **actual** contract the Flutter app implements (discovered from
`lib/core/network/api_client.dart`, `lib/features/auth/`, `lib/models/issue.dart`
and the test suite in `test/`). The Django backend in `backend/` implements
exactly this contract.

Base URL is a compile-time Dart value (`String.fromEnvironment('API_BASE_URL')`,
default `http://10.0.2.2:8000` in `lib/core/constants/api_constants.dart`).

- Emulator: `--dart-define=API_BASE_URL=http://10.0.2.2:8000`
- Physical phone: `--dart-define=API_BASE_URL=http://<PC-LAN-IP>:8000`

All endpoints return `application/json`. Success is any HTTP 2xx.

---

## Authentication

### `POST /api/auth/login/`

Request:

```json
{ "email": "citizen@example.com", "password": "secret" }
```

Response `200`:

```json
{
  "token": "9944b09199c62bcf9418ad846dd0e4bbdfc6ee4b",
  "user": { "id": 7, "email": "citizen@example.com", "first_name": "Jane", "last_name": "Doe", "phone": "+911234567890" }
}
```

### `POST /api/auth/register/`

Request:

```json
{
  "first_name": "Jane",
  "last_name": "Doe",
  "email": "citizen@example.com",
  "phone": "+91...",          // optional, omitted when empty
  "password": "secret"
}
```

Response `201` — same shape as login (`token` + `user`).

### Headers

Every request other than the two auth endpoints sends:

```
Authorization: Token <token>
```

The app parses `token`/`key`/`access` and stores the matching scheme
(`Token` or `Bearer`); this backend issues DRF token auth (`token`, scheme
`Token`).

### Auth error shapes

- Invalid login → `400` with `non_field_errors` (the app surfaces it):

```json
{ "non_field_errors": ["Unable to log in with provided credentials."] }
```

- Duplicate email on register → `400` with `email` list
  (must mention "already exists" for the app's test):
- Missing/invalid fields → `400` with `{ field: ["message", ...] }`.
- No/invalid token on a protected endpoint → `401`
  (`{"detail": "Authentication credentials were not provided."}`) — the app
  auto-logs-out on `401`.

Users are authenticated solely via the `Authorization` header (no CSRF needed).

---

## Issues

### `POST /api/issues/` — submit a civic issue

`multipart/form-data`. The Flutter app sends exactly these parts
(`lib/core/network/api_client.dart`, `submitIssue`):

| Field         | Type   | Notes                                |
|---------------|--------|--------------------------------------|
| `image`       | file   | `content-type: image/jpeg` (the app sends jpeg; backend accepts any valid image) |
| `latitude`    | string | e.g. `"28.6139"`                     |
| `longitude`   | string | e.g. `"77.2090"`                     |
| `description` | string | optional                              |

Requires authentication. Response `201`:

```json
{
  "id": 1042,
  "description": "Pothole near the crossing.",
  "image_url": "http://192.168.1.8:8000/media/issues/2026/01/01/photo_jpeg.jpg",
  "latitude": 28.6139,
  "longitude": 77.209,
  "address": "",
  "status": "reported",
  "created_at": "2026-01-01T10:30:00Z",
  "updated_at": "2026-01-01T10:30:00Z",
  "category": "other",
  "confidence": 0.0,
  "severity": "low",
  "duplicate": false,
  "duplicate_count": 0,
  "department": "Unassigned"
}
```

The app parses `id`, `status`, `category`, `confidence`, `severity`,
`duplicate`, `duplicate_count`, `department` from the submission response and
layers the local photo/GPS/description on top for display.

### `GET /api/issues/` — public feed (map + home)

Returns a **JSON array** (no pagination wrapper) of issue objects, newest
first, in the same flat shape as above. Public (no auth required).

### `GET /api/issues/{id}/` — public detail

Returns the single flat issue object. `404` when missing.

### `PATCH /api/issues/{id}/` — update

Authenticated. The reporter or staff may update status/fields with a JSON
body of changed fields. Non-owner → `403`.

### `GET /api/my-reports/` — the citizen's own reports

Requires auth. Returns a **JSON array** (no pagination wrapper) of the
authenticated user's issues, newest first.

---

## Issue object field reference

| Key              | Type              | Notes                                             |
|------------------|-------------------|---------------------------------------------------|
| `id`             | number            | parsed as string client-side                       |
| `description`    | string / null     |                                                   |
| `image_url`      | string / null     | absolute URL, rendered with `Image.network`        |
| `latitude`       | number            | **JSON number** — the app casts `as num?`          |
| `longitude`      | number            | **JSON number**                                    |
| `address`        | string / null     |                                                   |
| `status`         | string            | one of the STATUS values below                     |
| `created_at`     | ISO-8601 string   | used client-side for "newest first" sort          |
| `updated_at`     | ISO-8601 string   |                                                   |
| `category`       | string            | CATEGORY values below                              |
| `confidence`     | number            | 0.0–1.0                                           |
| `severity`       | string            | `low` / `medium` / `high` / `critical`            |
| `duplicate`      | boolean           | flat form used by the app                          |
| `duplicate_count`| number            |                                                   |
| `department`     | string            |                                                   |

The Flutter parser tolerates **either** flat keys (above) **or** a nested
`analysis` object with `category`, `confidence`, `severity`, `is_duplicate`,
`duplicate_count`, `department`. This backend emits the flat form.

### Enumerations

- **Status**: `reported`, `verified`, `assigned`, `in_progress`, `resolved`,
  `rejected` (the app also maps `submitted`, `pending`, `in-review`,
  `completed`, `cancelled` aliases for other backends).
- **Category**: `pothole`, `road_damage`, `garbage`, `streetlight`,
  `drainage`, `other`.
- **Severity**: `low`, `medium`, `high`, `critical`.

---

## Error handling

| Code | Meaning                     | Shape                                        |
|------|-----------------------------|----------------------------------------------|
| 400  | Validation error            | `{ field: ["message", ...] }` or `{"non_field_errors": [...]}` or `{"detail": "..."}` |
| 401  | Unauthenticated             | `{"detail": "Authentication credentials were not provided."}` |
| 403  | Forbidden (not your issue)  | `{"detail": "You do not have permission to perform this action."}` |
| 404  | Not found                   | `{"detail": "No Issue matches the given query."}` |
| 500  | Server error                | `{"detail": "..."}` (no stack traces in production) |

The app maps: 2xx → object/array; 400/422 with field lists →
`ValidationException`; `detail`/`error` strings → `ServerException`; 401 →
auto-logout; 404 → `ServerException("Resource not found.")`.

---

## Uploads

- `MEDIA_URL=/media/`, images stored under `MEDIA_ROOT/media/issues/YYYY/MM/DD/`.
- Validation: must be a Pillow-verifiable image, max 10 MB.
- Django serves `/media/` in DEBUG so `image_url` is loadable by the app.

## Auth method chosen

**DRF Token Authentication** (`rest_framework.authtoken`) — matches the app's
default `"Token"` scheme, is stateless for the app, and needs zero Flutter
changes (no refresh-token flow is implemented in the app yet).

---

# Appendix: Authority API (staff-only)

Base URL: same host under `/api/authority/`. Auth: session **or** DRF Token for
an `is_staff` user (403 for non-staff). This is the contract the React console
(`authority-web/`) implements.

## Endpoints

| Verb  | Path                               | Purpose                                        |
|-------|------------------------------------|------------------------------------------------|
| GET   | `/api/authority/meta/`             | Static-per-deployment metadata                 |
| GET   | `/api/authority/issues/`           | Filterable, orderable, pageable issue list     |
| GET   | `/api/authority/issues/<pk>/`      | Full authority detail (cluster + explanations) |
| PATCH | `/api/authority/issues/<pk>/`      | Staff dispatch (department / officer)          |
| POST  | `/api/authority/issues/<pk>/transition/` | Lifecycle status change                 |
| POST  | `/api/authority/issues/<pk>/resolve/`    | Resolution with BEFORE/AFTER evidence    |
| GET   | `/api/authority/stats/`            | Console dashboard counters + analytics        |
| GET   | `/api/authority/hotspots/`         | Priority-ordered heat-map cells               |

## `GET /meta/`

Serves enums (status/severity/category/priority class), `departments.assignable`
(routing-table labels + values actually in use + `Unassigned`),
`departments.by_category`, `scopes`, `ordering`, `officers` (staff users),
`lifecycle.valid_transitions`, and `capabilities`:

- `capabilities.spatial` — `{backend: "postgis"|"haversine", engine,
  distance_function, spatial_index, note, hotspot_cell_degrees}`. Honest: on a
  non-PostGIS DB it reports `haversine`/`none` and says so.
- `capabilities.priority_engine` — component catalogue, thresholds, weights and
  an honest note that priority is a deterministic rule model, not a trained one.
- `capabilities.vision` — what this deployment genuinely has (local perceptual
  hashing always; AI service only when configured).

## `GET /issues/` (list)

Query params (all optional):

| Param             | Semantics                                                       |
|-------------------|----------------------------------------------------------------|
| `scope`           | `masters` (default) \| `supporting` \| `all`                   |
| `status`          | one of the Issue status enums (unknown → 400)                  |
| `severity`        | `low`/`medium`/`high`/`critical` (unknown → 400)               |
| `category`        | one of the category enums (unknown → 400)                      |
| `priority_class`  | `low`/`medium`/`high`/`critical` (unknown → 400)               |
| `department`      | exact match on the stored department label                     |
| `assigned`        | `assigned` \| `unassigned` (anything else → 400)               |
| `priority_min/_max`| inclusive score window                                         |
| `created_after/before` | `YYYY-MM-DD` date window                                  |
| `lat_min/_max`, `lon_min/_max` | bounding box                                      |
| `q`               | description / address / reporter-email contains, or exact id   |
| `include_resolved`| if present, includes `resolved`/`rejected` rows                |
| `ordering`        | `priority` \| `newest` \| `oldest` \| `cluster` \| `severity` \| `reports` \| `status` (unknown → 400 listing valid keys) |
| `page`, `page_size` | opt into pagination; `page_size` clamped to 1..100          |

Response shapes:

- Without `page`: a plain array of issue objects.
- With `page`: `{"count", "page", "page_size", "total_pages", "results": [...]}`

Default hides resolved/rejected; unknown filter values are rejected outright with
a 400 so a stale console cannot silently query nonsense.

## Issue object (authority form)

The public flat mobile form plus:

```jsonc
{
  "master_id": 1,                // cluster root's id (self if standalone)
  "is_master": false,            // consolidates >=1 supporting report
  "cluster_size": 3,             // TOTAL citizen reports incl. the root
  "cluster_member_ids": [1, 4],
  "assigned_to": 12,             // staff user id or null
  "assigned_to_email": "...",
  "assigned_to_name": "...",     // first+last, else email
  "assigned_at": "2026-10-13T...Z",
  "duplicate_signals": {         // only on supporting rows that recorded it
    "signals": {"location": 0.95, "text": 0.7},
    "weights": {"location": 0.4, ...},
    "used_weights": {"location": 0.55, ...},  // renormalized, sum to 1.0
    "similarity_score": 0.81,
    "root_id": 1
  },
  "priority_explanation": {
    "score": 62, "class": "high",
    "engine": "rule-based-civic-analysis-v3",
    "engine_honest_label": "...",
    "reasons": [{"code": "duplicate_reports", "label": "...", "points": 8, "detail": "..."}],
    "components": {"severity": 30, "duplicate_reports": 8},
    "raw_total": 38,
    "inputs": {"category": "pothole", "severity": "high",
               "cluster_size": 3, "distinct_report_days": 1,
               "open_hours": 12.5, "mean_similarity": 0.81 /* null on masters */,
               "prior_reports_at_location": 1}
  },
  "vision": {...}, "analysis": {...},
  "resolution_status": "pending" | "verification-recorded" | "resolved",
  "master": {...},               // full detail for the cluster root (detail endpoint)
  "cluster": [...],              // member details (detail endpoint)
  "allowed_transitions": ["verified", "assigned", ...]  // never contains "resolved"
}
```

`mean_similarity` is `null` on master rows (they have no matched-report
similarity); `duplicate_signals` is `null` unless the engine recorded per-signal
evidence. Nothing is fabricated.

## `PATCH /issues/<pk>/` (staff dispatch)

Body (either or both): `{"department": "Road Maintenance", "officer_id": 12}`.
- `officer_id: null` unassigns (clears `assigned_to` and `assigned_at`).
- Unknown department → 400 with `{detail, allowed}`.
- Unknown/non-staff `officer_id` → 400.
Returns the full authority issue object.

## Priority scoring (why the console shows what it shows)

- Deterministic weighted **rule** model (`rule-based-civic-analysis-v3`).
- Components: severity base (cap 40), supporting reports (cap 20, 4 points per
  supporting report), freshness (10 within 24 h / 5 within 72 h), cluster-master
  bonus (5).
- Thresholds: low ≥ 0, medium ≥ 30, high ≥ 55, critical ≥ 80.
- `priority_model_score` is an *advisory* ML estimate when the AI sidecar
  produced one; it never overrides the rule score, and both stay separate in the
  payload.