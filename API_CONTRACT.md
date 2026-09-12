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