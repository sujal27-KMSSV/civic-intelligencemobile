# FixMyGrid — Hardening & Engineering Report (v1.0.2+3)

Generated: 2026-09-26
Scope: P0/P1/P2 hardening of the teammate-reported quality issues in the Flutter
app (`app/`) and Django API (`backend/`), release verification, on-device smoke
tests, and the final signed release artifact. Supersedes the interim
`PROJECT_AUDIT.md` / earlier `HARDENING_REPORT.md` notes for these phases.

---

## A. Status summary

**Engineering work: COMPLETE. All suites green; hardened backend LIVE; on-device
E2E verified.**

- Flutter: **151/151 tests pass**; `flutter analyze` = **0 errors / 0 warnings**
  (only the 2 pre-existing `prefer_const_constructors` infos in
  `test/api_client_test.dart`).
- Django: **79/79 tests pass**.
- Production API (`https://civic-intelligence-api.onrender.com`): **hardened
  backend is now LIVE** — server flags (`can_edit` / `can_delete`), the citizen
  PATCH allow-list, and the 10-minute delete window are enforced on Render (see
  §D for the live checks).
- On-device E2E (real hardware, real production API): **both device tests
  pass**, including a genuine camera photo, gallery photo, edit, delete within
  the window, and cross-account data isolation (see §G).
- A **real account-isolation bug** surfaced by the device tests was found and
  fixed (see §B/P0) — switching accounts could briefly serve the previous
  user's cached reports until the provider refetched.
- Final signed release artifact rebuilt from the fixed code: **v1.0.2 (code 3)**,
  confirmed signer and embedded base URL (see §F).

---

## B. What changed

### P0 — Account-isolation on session switch (new, found by on-device E2E)
- **Bug**: `myReportsProvider` (and the public feed) were never invalidated on
  `login` / `register` / `logout`. Because both are long-lived `AsyncNotifier`
  / `FutureProvider` instances, after A logs out and B registers the My Reports
  tab served A's **cached** list until some other action forced a refetch —
  a genuine cross-user data-visibility flaw (and the reason the on-device
  two-account run initially showed A's 4 reports for a freshly registered B).
- **Fix**: `AuthNotifier` now calls `_refreshUserScopedState()` — which
  invalidates `myReportsProvider` and `issueFeedProvider` — on every successful
  `login`, `register`, and `logout`. The next visit to Reports/Home/Map always
  performs a fresh, correctly-authenticated fetch.
- Covered by the on-device E2E (A→B→A→B switching with `No reports yet` /
  `4 reports` / `1 report` assertions at each step).

### P0 — Auth & session reliability (carried over)
- `AuthStorage` + `SecureAuthStorage` persist/restore `first_name` /
  `last_name` alongside the token; a restart no longer loses the display name.
- `AuthRepository.restoreSession` returns the full `User` without network.
- `authNoticeProvider` gives a human-readable reason after a 401 auto-logout
  ("Your session has expired…"), shown on the login screen and cleared on the
  next attempt.
- Logout and the 401 path both clear the session from secure storage.

### P0 — Backend authorization & server-authoritative buttons (carried + live)
- `issues/window.py`: `DELETE_WINDOW_MINUTES = 10` computed from the server
  clock.
- `perform_update` allows citizens to PATCH only `description` + `address`
  (else **403** listing every disallowed field); `perform_destroy` enforces the
  10-minute window for non-staff (staff lifecycle unchanged).
- Serializers surface read-only `can_delete` / `can_edit`; the client renders
  Edit/Delete **only when the server says so** (no device-clock logic).
- `accounts/throttles.py` + settings: login/register rate limit
  (`AUTH_THROTTLE_RATE`, default `10/min` per IP), scope `auth`.

### P0 — Submission reliability (carried + live)
- `multipartPost` retried once through `_guardWithRetry`; a dropped connection
  surfaces a `NetworkException` instead of hanging forever; every submit carries
  a stable `client_request_id` and the backend de-duplicates on it
  (`0005_client_request_id`, live).
- `PATCH` also retried (idempotent absolute values).
- Result screen: leave-while-loading allowed; the loading page cannot be popped
  once the submit has succeeded.

### P0 — Image validation agrees client↔server (carried + live)
- Server: min shorter-edge **320 px**, pixel-bomb cap **24 MP**, file cap
  **10 MB**; real pixel size re-read (header-only / 1×1 files rejected).
- Client: rejects picks under 320 px with a clear message.

### P1/P2 (carried)
- Edit UI: `report_edit_dialog.dart` (description + address only, inline errors,
  saving spinner) reachable from My Reports (server-flag gated) and Issue
  Details; both invalidate providers and confirm with a snackbar.
- `context.push` for card/detail navigation so system Back returns to the feed
  instead of quitting; cards show address + coordinates + Created/Updated;
  bottom padding so CTAs are not covered.
- M3 theme polish (chips, snackbars, nav-bar states, brand-colored selection).

---

## C. Test results (final pass)

| Suite | Result |
|---|---|
| Flutter `flutter test` | **151/151 passed** |
| Flutter `flutter analyze` | 0 errors, 0 warnings, 2 pre-existing `info` |
| Django `manage.py test` | **79/79 passed** |
| On-device `two_account_e2e_test` | **PASSED** (2:35) |
| On-device `network_failure_e2e_test` | **PASSED** (0:14) |

The two device tests run against the **real production API** with a genuine
640×480 PNG photo (drawn at runtime with `dart:ui`, so no added dependencies)
and production test accounts. `app_e2e_test.dart` (legacy device suite) was
updated to the same valid-photo helper.

---

## D. Production verification (live)

- `GET /api/issues/?limit=1` → **200**; global feed has **18 issues**.
- `GET /api/issues/21/` → includes `can_edit=True`, `can_delete=False` →
  **hardened server flags are live**.
- Citizen `PATCH /api/issues/21/ {"latitude": ...}` → **HTTP 403** (allow-list
  enforced live).
- Account A (`finaldemo20260923x@example.com` / `Demo@1234`) → exactly **4
  legacy reports** after all E2E runs; **zero** E2E leftovers in the feed.
- Auth rate limiting: implemented and unit-tested (429 after 10
  rapid logins); the explicit 11-login live probe was verified in the prior
  phase and today's targeted repeat was inconclusive only due to IP-throttle
  side effects on the probe itself (all requests were 400 from a garble of the
  shell-escaped JSON body, not from the app).
- Durable media: **R2/S3 storage is still not configured** — media lives on
  Render's ephemeral disk (limitation, see §H).

---

## E. Deployment status (Render)

**Deployed.** The current `main` (head = hardened code incl. migration
`0005_client_request_id`) is live on `civic-intelligence-api.onrender.com`;
Render applies `migrate` → `collectstatic` → `gunicorn` on boot. Verified live:
server flags, citizen PATCH allow-list, and the delete window. Optional env
`AUTH_THROTTLE_RATE` (default `10/min`) remains available.

---

## F. Release artifact (final, signed)

Built from the current `main` with
`--dart-define=API_BASE_URL=https://civic-intelligence-api.onrender.com`,
release-signed with the upload keystore, and verified:

- `release\FixMyGrid-Hardened.apk` (= `release\FixMyGrid.apk`)
  - versionName **1.0.2**, versionCode **3**
  - appId `com.civicintelligence.civic_intelligence`
  - minSdk 24 / targetSdk 36
  - **SHA-256 `9027E6276BCCAFE60AAA7F573990938ABF86848796B89367F4BBB4CAA5C35F52`**
  - `apksigner` verify: Signer #1 **CN=Civic Intelligence**, O=Civic
    Intelligence, L=Public, ST=Public, C=IN (v2 scheme OK)
  - embedded base URL scan of `libapp.so`: `onrender.com` present; **no**
    `10.0.2.2` / `127.0.0.1` / `192.168.*` / `api.example.com` refs
    (`localhost` hit is Flutter engine diagnostics, not a URL)
- `release\FixMyGrid.aab` (Play-distributable) — SHA-256
  `07F582B75CC07C5C65D7659A679DCFF1494A6D47EEA9B8490352EC5E2D155518`

---

## G. On-device verification (completed)

Device `ZD2224MKS4` (motorola edge 20 fusion), build-tools
`C:\Android\Sdk\build-tools\36.0.0\`, prod API, prod test accounts.

1. **`two_account_e2e_test.dart` PASSED (2:35)** against live prod:
   - A: login → My Reports `4 reports` (legacy, no Delete button) → create a
     **camera** report (real runtime-generated PNG) → `5 reports` → detail →
     back → **edit** (Edit dialog → `Report updated.`) → **delete** (Delete
     dialog → `Report deleted.`) → `4 reports` → logout.
   - B (fresh account): register → My Reports **`No reports yet`** (isolation
     from A) → create a **gallery** report → `1 report` → edit → logout.
   - A again: `4 reports`, B's descriptions **absent** → logout.
   - B again: `1 report` with its **edited** description (edit survived the
     session switch) → delete → `No reports yet` → logout.
2. **`network_failure_e2e_test.dart` PASSED (0:14)**: home feed error state
   (`Could not load reports`, Retry) under a failing repository → Retry recovers
   the feed → a simulated relaunch restores the signed-in session with the feed.

Infrastructure note: the test phone's PIN keyguard cannot be dismissed over adb
and pauses the app's frame pipeline when it engages; runs therefore require the
screen to be manually unlocked when it relocks. The two-account test also
exposed the account-isolation bug (§B) that is now fixed.

---

## H. Known limitations / follow-ups

- **R2/durable media storage not configured** — user-uploaded photos live on
  Render's ephemeral disk and can be lost on instance recycle; this is the
  single remaining infra hardening item.
- Delete is intentionally limited to the 10-minute window (retraction
  semantics); long-term moderation/removal stays staff-only.
- The auth throttle is per-IP (`10/min` default) — a shared-NAT office could
  see transient 429s during bursts; fine for now, tune via
  `AUTH_THROTTLE_RATE` if needed.
- Layout heuristics were finally verified on a real device (a prior §H note).

## I. Production-safety confirmation

No destructive migrations, no secrets added, no auth/authorization weakened,
no demo bypasses or fake responses. Two changes *tighten* security this phase:
the citizen PATCH allow-list (already live) and the account-isolation
refresh-on-session-switch fix (in this APK). All behavior is covered by
automated tests.