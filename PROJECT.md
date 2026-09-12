# Civic Intelligence — Mobile App

AI-powered smart-city civic reporting platform (Flutter + Django REST backend).
Citizens report issues with a photo and GPS location; the backend classifies the
photo (category, severity, confidence, duplicates) and routes it to the right
department.

- **Android app ID:** `com.civicintelligence.civic_intelligence`
- **Version:** `1.0.0+1` (from `pubspec.yaml`)
- **Min SDK:** Flutter default (`flutter.minSdkVersion`, ≥ 21)
- **State management:** Riverpod 2 (`flutter_riverpod`)
- **Routing:** `go_router`

---

## Getting started

```bash
flutter pub get

# Debug build for an Android emulator against a local Django backend:
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Physical Android device, Django running on the dev machine's LAN IP:
flutter run --dart-define=API_BASE_URL=http://192.168.1.50:8000
flutter build apk --release --dart-define=API_BASE_URL=http://192.168.1.50:8000
```

The API base URL is a compile-time value (`String.fromEnvironment('API_BASE_URL')`,
see `lib/core/constants/api_constants.dart`). The app's default is
`http://10.0.2.2:8000`, which is the Android-emulator alias for the host —
a development-only value. **A physical phone cannot use `10.0.2.2`/`localhost`;
pass a LAN-reachable IP or a real hostname.** Production builds must pass
`--dart-define=API_BASE_URL` with an HTTPS URL.

Cleartext HTTP is enabled in the main manifest (`usesCleartextTraffic`, so
debug **and release**) because the demo backend is served over `http://`.

#### The backend must listen on the LAN, not just localhost

`python manage.py runserver` binds to **127.0.0.1 only** by default. A physical
phone can never reach that, so from the machine that hosts Django start it with:

```bash
python manage.py runserver 0.0.0.0:8000
```

Then build/run the app pointed at that machine's LAN IP (find it with `ipconfig`),
not at `10.0.2.2`/`localhost` (see the commands above).

Symptom if either the base URL is wrong **or** Django is bound to localhost:
login/signup stalls ~20s and reports
`"Server took too long to respond. Please try again."` (the app's `TimeoutException`
in `ApiClient._guard` — `lib/core/network/api_client.dart`). Windows Firewall may
also block inbound port 8000; allow it for private networks if the phone still
cannot connect.
Once the API moves to HTTPS, remove that attribute.

Android release builds are signed with the **debug key** so the hackathon demo can
be installed directly (`flutter build apk --release`). Do your own signing config
before store upload (see `android/app/build.gradle.kts`).

---

## Architecture

```
lib/
├─ core/
│  ├─ constants/        api_constants, app_constants, colors, severity_colors
│  ├─ errors/           AppException family (Network/Server/Auth/Validation)
│  ├─ network/          ApiClient (HTTP wrapper, auth header, error mapping),
│  │                    AuthStorage (secure token storage)
│  ├─ theme/            AppTheme (Material 3)
│  └─ widgets/          AppLogo, EmptyState, IssueCard, StatusChip, SeverityChip
├─ features/
│  ├─ auth/             login/register screens, AuthState/AuthNotifier,
│  │                    AuthRepository, typed request/response models
│  ├─ feed/             IssueFeedRepository/Provider — single cached public
│  │                    issue feed shared by Home and Map (falls back to
│  │                    my-reports when GET /api/issues/ is missing)
│  ├─ issues/           MyReportsScreen/Provider (AsyncNotifier + status-change
│  │                    notifications), IssueDetailsScreen, issue details provider
│  ├─ map/              MapScreen (flutter_map), markers from the shared feed
│  ├─ notifications/    In-app notification centre (model, notifier, screen)
│  ├─ profile/          ProfileScreen
│  ├─ reporting/        ReportDraft (state model), issue/review/result screens,
│  │                    ReportSubmissionProvider, ReportRepository
│  └─ splash/           session-restore splash
├─ models/              Issue (+IssueStatus & AI analysis), User, LocationPoint
├─ routing/             go_router config with auth-guard redirect
└─ services/            media_service (camera/gallery), location_service (GPS),
                        notification_service (push seam)
```

**Layering rule:** widgets never talk to `ApiClient` directly — they call
repositories/providers. Separate service interfaces (`MediaService`,
`LocationService`, `NotificationService`) keep platform and backend concerns
swappable.

**Riverpod providers** (hand-written, no codegen):
`authProvider` → `authRepositoryProvider` → `apiClientProvider` →
`authStorageProvider`; plus `reportRepositoryProvider`, `issueFeedRepositoryProvider`,
`issueFeedProvider` (the shared feed), `issueDetailsProvider`, `myReportsProvider`,
`notificationCenterProvider`, `notificationServiceProvider`.

---

## Key flows

### Authentication
- Login/register call `POST /api/auth/login/` and `POST /api/auth/register/`
  (Django auth). The app accepts the standard DRF `token`/`key` and SimpleJWT
  `access`/`refresh` response shapes and sends the matching `Authorization`
  scheme (`Token` or `Bearer`). The session (token + scheme + optional refresh)
  is persisted in **`flutter_secure_storage`** (`AuthStorage`), never
  SharedPreferences.
- `ApiClient` attaches the `Authorization` header to every request and, on
  HTTP 401, fires `onUnauthorized`, which logs the user out automatically.
- The router guard (`lib/routing/app_router.dart`) shows splash while the session
  restores, then redirects signed-out users to `/login`. `/issue/:id` is the only
  path reachable signed-out (shared public links). Login/register screens are not
  torn down while a request is in flight, so backend errors render on the form
  instead of bouncing to login.
- Build with `--dart-define=DEBUG_AUTH=true` to log auth response status + key
  names (never credential values) and verify the backend contract.

### Reporting
1. Category → photo (camera/gallery, compressed) → location (GPS + reverse
   geocoding) → description → review.
2. Submit = multipart `POST /api/issues/` (photo + lat/lng + description).
3. Success screen shows the AI analysis (category, confidence, severity,
   duplicate count, department) returned by the backend.
4. The report appears in **My Reports** (`GET /api/my-reports/`) and flows into
   the home feed and map.

### Notifications
- `NotificationService` is an abstraction. The shipped `LocalNotificationService`
  records events in an in-app notification centre; there is **no push channel**
  configured yet.
- A submission confirmation is added on success; **status changes** are detected
  by `MyReportsNotifier` when the report list is refreshed and comparing against
  the previous snapshot (e.g. pulling to refresh in My Reports after a city
  official updates the issue).
- To enable real push later: implement `NotificationService` (e.g. Firebase Cloud
  Messaging) and point `notificationServiceProvider` at it, keeping credentials
  out of source. Build with `--dart-define=PUSH_NOTIFICATIONS_ENABLED=true`.

---

## Performance & UX

- **Shared issue feed.** Home and the Map tab read the same cached
  `issueFeedProvider`; refreshing one refreshes both and submitting a report
  invalidates it (`ref.invalidate(issueFeedProvider)`).
- **Splash.** The fixed 2.2s branding delay is gone. The router redirect leaves
  `/splash` the moment the session is restored, and the feed is pre-warmed in
  the background during restore.
- **Issue details.** Opening from a list reuses the already-loaded `Issue`
  (no by-id fetch); pull-to-refresh still refetches. Deep links fetch by id.
- **Images.** Photos picked for reports are recompressed on-device
  (`flutter_image_compress`, quality 72, only when over ~400KB); decoded image
  dimensions are capped via `cacheWidth` on the details header and photo cards.
  `cached_network_image` is also available for the network image cache.
- **JSON parsing.** Large list payloads (issue feed) are decoded on a background
  isolate (`Isolate.run` above a 64KB threshold) so the UI thread stays
  responsive.
- **Map location.** `currentLocationProvider` uses medium-accuracy GPS and skips
  reverse geocoding (the marker doesn't need an address); report capture still
  asks for full accuracy and an address.
- **Report description.** The draft commits on focus loss / review / back
  instead of per keystroke, so typing doesn't rebuild the screen.
- **Submission.** The multipart submit allows up to 60s (backend upload + AI
  inference is a single synchronous request); the loading screen cycles through
  elapsed-step messages so a slow request doesn't look frozen. True async
  submission would require a backend change (return a job id, then poll).
- **Perf timing.** Build with `--dart-define=PERF_TIMING=true` to log API, splash
  restore and feed-warm timings (`lib/core/utils/perf.dart`). No-op otherwise.

---

## Statuses

The app understands the backend lifecycle: `reported`, `verified`, `assigned`,
`in_progress`, `resolved`, `rejected` (see `IssueStatus.parse` in
`lib/models/issue.dart`). Status chips, the details timeline, My Reports filters
and notification messages all use these labels.

---

## Testing

```bash
flutter test        # unit + widget tests
flutter analyze     # static analysis (must be clean)
```

Test doubles live in `test/test_utils.dart` (`InMemoryAuthStorage`,
`FakeReportRepository`, `FakeMediaService`, `FakeLocationService`,
`testTileProvider`). Widget tests that touch the map inject `testTileProvider()`
to avoid the flutter_test HTTP stub.

---

## Project checklist status

- [x] Login / register / logout with secure token storage and session restore
- [x] Report submission with camera, gallery, GPS and AI analysis display
- [x] My Reports list with status filters and pull-to-refresh
- [x] Interactive map of civic issues
- [x] Issue details with status timeline and duplicate banner
- [x] In-app notifications (submission + status change)
- [x] Home feed backed by the real API (no mock data in the UI)
- [ ] FCM/APN push notifications (service seam ready)
- [ ] Play-Store signing config (release uses the debug key)
- [ ] Production app icon / splash polish

---

## Manual demo script (hackathon)

1. Register a fresh account (or log in) against the demo backend.
2. Home shows the public feed, real stats and your name.
3. **Report an Issue** → pick a category, take/store a photo, capture location,
   add a description → review → submit.
4. Success screen: AI category, confidence bar, severity badge, duplicate banner,
   responsible department.
5. **View My Reports** → find the new report (status `Reported`) → open it → the
   details screen shows the analysis, timeline and duplicate info.
6. Pull to refresh (My Reports and the details screen) — if a city operator
   advanced the issue status, an in-app **notification** appears (bell badge on
   Home, and under the Notification bell/Profile → Notifications).
7. Map tab shows markers; tapping a marker opens the issue.
8. Log out from Profile → session cleared and login shown.