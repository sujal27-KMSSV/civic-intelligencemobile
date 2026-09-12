# Civic Intelligence — Project Audit

Date: 2026-09-12
Scope: Flutter mobile app + Django REST backend (working copy `C:\dev\civic-intelligencemobile`, byte-identical to the OneDrive originals).

## 1. Completed functionality

### Mobile (Flutter)
- Splash with session-restore pre-warm and feed pre-warm
- Register / Login / Logout with DRF token auth; secure storage of tokens (flutter_secure_storage, Android Keystore-backed)
- Home dashboard: greeting, reports stats (Reports/Open/Resolved), quick-report CTA, live feed of issues
- Report builder (3 steps): category selection, camera/gallery + retake/remove, image auto-compression (>400 KB -> JPEG q72), GPS capture with permission/settings handling + reverse geocoding, optional description with 500-char counter
- Review screen + submit with multipart upload and progress states (loading / success / error + retry)
- Result screen showing backend AI-analysis payload
- My Reports with status filter chips and FAB
- Issue details: photo (cached), location, department, status timeline, duplicate banner
- Interactive OSM map (flutter_map) with severity-colored markers + user-location dot + selected-issue card
- In-app notification center
- Profile: user card, language/help/about, logout with confirmation
- Network layer: JSON + multipart, isolate parsing for large payloads, 401 -> auto-logout hook, typed exceptions (Network/Auth/Server/Validation), DEGRADED demo fallback in feed repository
- On-device integration test (register->logout->login->report->my-reports->details) — passing against the real backend

### Backend (Django)
- Custom email-based `User` (no username), unique email, custom manager
- `Issue` model: category/severity/status choices, GPS decimals, image upload, AI-reserved columns, self-FK `duplicate_of`, timestamps, ordering
- `/api/auth/register/`, `/api/auth/login/` returning `{token, user}`
- `/api/issues/` public feed + detail; POST authenticated + owner/staff allowed; PATCH owner/staff only
- `/api/my-reports/` authenticated own-reports feed
- Image validation (max 10 MB, PIL verify, must be an image)
- Admin: user admin + issue admin with filters/search/AI fieldset
- 24 automated tests (auth 8 + issues 16), `manage.py check` clean
- `.env.example`, SQLite dev DB / PostgreSQL switch via env

## 2. Incomplete functionality

- **AI / civic intelligence: NOT implemented anywhere.** AI columns exist with honest defaults only (see §3-5). No image classification, no severity scoring, no duplicate detection, no clustering, no embeddings, no department routing.
- **Authority side: not implemented.** No authority API, no dashboard (web or mobile), no staff workflow (assign/update/resolution upload/verification).
- **Issue lifecycle: partial.** Status enum full (reported/verified/assigned/in_progress/resolved/rejected) and owner can PATCH status, but there is no validation of the lifecycle transitions, no resolution fields (after-photo, notes, timestamps), and no resolution verification.
- **Production deployment config: none.** No gunicorn/whitenoise/Docker/Procfile; static served by dev server; media only served while `DEBUG=True`.
- No management commands (e.g., no seed/demo command, no createsuperuser shortcuts documented as commands).
- No pagination or throttling on the API.

## 3. Bugs

- None known at time of writing that block the primary flows (found + fixed through this release cycle: phone firewalled off backend, OneDrive reparse-point breaking Gradle release builds, snackbar overlay eating submit taps in automation). All have been verified fixed.

## 4. Security issues

- `SECRET_KEY` falls back to an insecure literal when env missing (`config/settings.py:16`).
- `DEBUG` defaults to `True` (`settings.py:9`).
- `ALLOWED_HOSTS` defaults to `*` (`settings.py:18`).
- `CORS_ALLOW_ALL_ORIGINS` defaults to `True` ("Hackathon CORS", `settings.py:49`).
- `android:usesCleartextTraffic="true"` in the Android manifest (required for LAN demo; MUST be removed/flag-gated for the public HTTPS build).
- Release APK is signed with the debug key (fine for hackathon demo, NOT for store submission).
- No request throttling -> brute-force registration/login not rate limited.
- Passwords: hashed server-side, never logged; token payload never logged (DEBUG_AUTH logs key names only). Confirmed no secrets committed.

## 5. Deployment blockers

- No reachable HTTPS backend exists (see release docs). Public APK **cannot** point at a real URL until one is deployed — the single manual step is creating the hosting account + DNS (credentials not available in this environment).
- Backend needs production process+static/media serving + env-gated secure settings (prepared in this release cycle).
- Media storage on local disk is fine for demo; production should move to object storage.
- App default `API_BASE_URL` is `http://10.0.2.2:8000` (emulator localhost) — must always be overridden with `--dart-define`; LOCAL DEMO build pins the LAN URL.

## 6. UX issues

- Profile shows `citizen@example.com` fallback when the user object is missing email — looks like a hardcoded demo address.
- Map `userAgentPackageName` still uses the `com.example...` template string.
- Map defaults to a hardcoded center (New Delhi) until GPS resolves — acceptable for a demo, documented.
- Authoritative "AI" copy exists in the UI while the backend returns honest defaults (`confidence 0.0`, `severity low`, `department Unassigned`) — MUST be labeled honestly until real analysis runs (addressed in this release cycle).

## 7. Testing gaps

- No backend tests for civic analysis / authority APIs / lifecycle transitions / resolution verification (added in this release cycle).
- No Flutter widget tests for authority UI (none exists — out of scope by design; authority is the web dashboard).
- E2E covers happy path only; error/retry paths are unit-tested on the client side (report_result error/retry tests exist).

## 8. Release blockers

- Public APK without a real HTTPS backend (by rule, the public APK is deferred until the backend is deployed; LOCAL DEMO APK is the verified deliverable).
- Release signing uses the debug key — acceptable for LOCAL DEMO, documented as the step to change for store upload.
- Cleartext HTTP must be removed/gated for the production build (documented; LOCAL DEMO requires it).