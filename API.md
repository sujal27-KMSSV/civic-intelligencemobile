# Civic Intelligence — API contract

Describes the Django REST endpoints the mobile app talks to, as implemented in
`lib/core/constants/api_constants.dart`, `lib/core/network/api_client.dart` and
the repositories.

**Base URL:** compile-time `API_BASE_URL` dart-define (development default
`http://10.0.2.2:8000` — emulator-only alias for the host; a physical phone must
be pointed at the LAN IP/hostname, e.g. `--dart-define=API_BASE_URL=http://192.168.1.50:8000`).
Production must be HTTPS. Cleartext `http://` is permitted from debug and release
builds via `android:usesCleartextTraffic` in the main manifest.

**Authentication:** every endpoint except the two auth endpoints requires the
header `Authorization` with the session credential (`Token <token>` for DRF
token auth, `Bearer <access>` for JWT). The app auto-selects the scheme from
the login/register response (`token`/`key` → `Token`, `access` → `Bearer`). On
HTTP `401`, the app logs the user out.

**Diagnostics:** build with `--dart-define=DEBUG_AUTH=true` to log the HTTP
status and top-level key names of auth responses (`[auth] ...`). Credential
values are never logged.

---

## Auth

### `POST {base}/api/auth/login/`

Request (`application/json`):

```json
{ "email": "citizen@example.com", "password": "secret" }
```

Response `200`:

```json
{
  "token": "django auth token",
  "user": { "id": 1, "email": "citizen@example.com",
            "first_name": "...", "last_name": "...", "phone": null }
}
```

### `POST {base}/api/auth/register/`

Request:

```json
{
  "email": "citizen@example.com",
  "password": "secret",
  "first_name": "Nina",
  "last_name": "Sharma",
  "phone": "+91..."
}
```

Response `201` — same shape as login (token + user).

**Accepted auth response shapes** (login and register): DRF token auth
`{"token": ..., "user": {...}}`, DRF `key` style `{"key": ...}`, or SimpleJWT
`{"access": ..., "refresh": ..., "user": {...}}`. The app sends the matching
`Authorization` scheme (`Token` or `Bearer`). If none of `token`/`key`/`access`
is present, the app reports
"The server did not return a session token." instead of failing silently.

**Errors** (both endpoints):

| Status | Meaning | Handling |
| ------ | ------- | -------- |
| `400` / `422` | Validation errors (e.g. duplicate email, bad password) | `ValidationException` with per-field messages (`field: [msg]`) or a `detail`/`error` string; shown under the fields / form banner |
| `401` | Invalid credentials | Shown as "Invalid email or password" |
| network / timeout | Server unreachable | `NetworkException`, friendly retry message |

---

## Issues

### `POST {base}/api/issues/`

Multipart form (`multipart/form-data`), authenticated. The client allows up to
**60 seconds** for this call: the backend uploads the photo, detects duplicates
and runs AI classification in one synchronous request. Photos smaller than
~400KB are sent as-picked; larger ones are recompressed on-device first.

Fields: `latitude` (string number), `longitude` (string number),
`description` (optional string), `image` (JPEG photo).

Response `201` — the AI analysis result:

```json
{
  "id": 1043,
  "status": "reported",
  "category": "Pothole",
  "confidence": 0.96,
  "severity": "CRITICAL",
  "duplicate": false,
  "duplicate_count": 0,
  "department": "Roads"
}
```

### `GET {base}/api/issues/`

Public list of all civic issues. Fetched once and shared by the home feed and
the map (single cached `issueFeedProvider`). If the endpoint is missing
(HTTP `404`), the app falls back to `GET /api/my-reports/` so the map still
works for older backends. Large payloads are decoded on a background isolate.

Response `200` — array of issue objects (flat analysis fields):

```json
[
  {
    "id": 1042,
    "category": "Pothole",
    "confidence": 0.96,
    "severity": "CRITICAL",
    "status": "in_progress",
    "created_at": "2026-01-05T09:00:00Z",
    "latitude": 12.9716,
    "longitude": 77.5946,
    "address": "MG Road, Block C",
    "description": "...",
    "image_url": "...",
    "duplicate": false,
    "duplicate_count": 0,
    "department": "Roads"
  }
]
```

### `GET {base}/api/issues/{id}/`

Single issue detail (used by the details screen to refresh status).

Response `200` — same flat-object shape as the list items above.

### `GET {base}/api/my-reports/`

Authenticated list of the current user's reports (newest first).

Response `200` — array of the same issue-object shape as `GET /api/issues/`.

---

## Status lifecycle

`status` values recognised by the app:

| value          | label        |
| -------------- | ------------ |
| `reported` (`submitted`, `pending`) | Reported |
| `verified` (`in_review`, `reviewing`) | Verified |
| `assigned`     | Assigned     |
| `in_progress`  | In Progress  |
| `resolved` (`completed`, `closed`)   | Resolved     |
| `rejected` (`cancelled`) | Rejected |

Unrecognised values degrade to `unknown`.

---

## Error model (all endpoints)

`ApiClient` normalises failures into `AppException` subtypes
(`lib/core/errors/app_exception.dart`):

- `NetworkException` — timeout / connection refused.
- `ServerException` — 5xx, 404, unexpected bodies, `detail`/`error` strings.
- `ValidationException` — 400/422 with a `field: [errors]` map.
- `AuthException` — 401 (also triggers automatic logout).

The UI shows these as friendly inline messages or retry screens.