# FixMyGrid — Hardening & Engineering Report (v1.0.1+2)

Generated: 2026-09-25
Scope: P0/P1/P2 hardening of the teammate-reported quality issues in the Flutter
app (`app/`) and Django API (`backend/`), plus release verification and the APK
decision. Supersedes the interim `PROJECT_AUDIT.md` notes for these phases.

---

## A. Status summary

**Engineering work: COMPLETE.** All suites are green.

- Flutter: **151/151 tests pass**; `flutter analyze` = **0 errors / 0 warnings**
  (only the 2 pre-existing `prefer_const_constructors` infos in
  `test/api_client_test.dart`).
- Django: **79/79 tests pass** (was 67 before this pass; +12 new tests).
- Production API: running, but **NOT yet redeployed** — see §D. The new backend
  behavior (server-side `can_delete`/`can_edit`, citizen PATCH allow-list,
  10-minute delete window, auth rate limiting) is **not live on Render**.
- Release APK: the existing **verified `FixMyGrid.apk` remains the production
  artifact** and is the *correct* pairing with the currently-live backend.
  Sequence for a new APK is documented in §F — do **not** build it until the
  backend is redeployed (the new client trusts server flags that today's prod
  does not return).

---

## B. What changed

### P0 — Auth & session reliability
- `AuthStorage` + `SecureAuthStorage` now persist/restore `first_name` /
  `last_name` alongside the token (`readUserFirstName`, `readUserLastName`,
  `saveSession(firstName:, lastName:)`). A restart no longer loses the display
  name.
- `AuthRepository.restoreSession` returns the full `User` (name included) from
  storage without hitting the network.
- `auth_state.dart`:
  - new `authNoticeProvider` — a human-readable reason the user was signed out.
  - `login`/`register` reset state to `AsyncData(AuthState.unknown())` **before**
    firing so a stale error banner disappears immediately and the form stays on
    screen (no torn-down loading state).
  - the networking layer's 401 handler (`buildUnauthorizedCallback`) sets
    *"Your session has expired. Please sign in again to continue."* then logs
    out — `login_screen.dart` shows it as a blue info banner, cleared on the
    next sign-in attempt.
- Logout and the 401 path both clear the session from secure storage.

### P0 — Backend authorization & server-authoritative buttons
- `issues/window.py`: `DELETE_WINDOW_MINUTES = 10`,
  `delete_window_expired(created_at)` computed from the **server clock (UTC)**.
- `issues/views.py` `perform_update`:
  - citizens may only PATCH `description` + `address` (any other field →
    **403** listing every disallowed field);
  - `perform_destroy` enforces the 10-minute window for non-staff;
  - staff lifecycle unchanged (authority-owned fields).
- `issues/serializers.py`: read-only `can_delete` (`!delete_window_expired`) and
  `can_edit` (`status in (reported, verified)`) surfaced on detail + list +
  my-reports payloads. The client renders Edit/Delete actions **only when the
  server says so** — no device-clock logic (fixes the delete-button
  inconsistency and the "old report still deletable" bug).
- `accounts/throttles.py` + `accounts/views.py` + `config/settings.py`:
  **login/register rate limit** `AUTH_THROTTLE_RATE` (default `10/min` per IP),
  scope `auth` on both views.
- Migration `backend/issues/migrations/0005_client_request_id.py` (idempotent
  submission de-dup key) exists but is **not deployed** — see §D/§E.

### P0 — Submission reliability
- `ApiClient.multipartPost` is now retried once through `_guardWithRetry`
  (`retryTimeout`, default 60 s, configurable for tests). A dropped connection
  (never-completing server) surfaces a `NetworkException` in ~1–2 min instead of
  hanging the "Still working…" spinner forever. Safe from duplicates because
  every submit carries a stable `client_request_id` and the backend de-dups on
  it (migration 0005).
- `PATCH` also goes through `_guardWithRetry` (idempotent absolute values).
- Result screen: during a submission the user can leave via a Back/close button;
  the loading page can no longer be popped once the submit has **succeeded**.

### P0 — Image validation (client + server agree)
- Server (`issues/validators.py`): min dimension **320 px** on the shorter edge,
  pixel-bomb cap **24 MP** (`MAX_IMAGE_PIXELS`), file cap **10 MB**; the file is
  re-opened and its real pixel size read (a header-only / 1×1 file no longer
  passes).
- Client (`media_service.dart`): rejects picks under 320 px with *"Please upload
  a clear photo of the reported civic issue."*

### P1 — Edit UI
- `ReportRepository.updateIssue(id, {description, address})` (+ API impl via
  `ApiClient.patch`); Fake implementations updated.
- New `lib/core/widgets/report_edit_dialog.dart`: edits description + address
  only (coordinates/photo/analysis stay authority-owned), inline errors, saving
  spinner.
- Entry points in **My Reports** (Edit/Delete action row, server-flag gated) and
  **Issue Details** (AppBar edit icon when `canEdit`). Both invalidate the
  relevant providers after save and confirm with a "Report updated." snackbar.

### P1 — Back navigation & card info
- `issue_card.dart` and `map_screen.dart` use `context.push` so the system Back
  gesture returns to the feed/map instead of quitting.
- Issue cards now show: friendly address (primary) **plus** coordinates as a
  secondary line when both exist, and "Created \<date\> · Updated \<date\>"
  (fallback "Uploaded recently"). Tabular figures keep timestamps aligned.
- Report-list bottom padding increased so the primary CTA is not covered by the
  bottom navigation bar.

### P2 — Theme polish
- `app_theme.dart`: consistent chip styling, floating rounded snackbars, M3
  navigation-bar indicator/icon states, and brand-colored text selection.

---

## C. Test results (this pass)

| Suite | Result |
|---|---|
| Flutter `flutter test` | **151/151 passed** |
| Flutter `flutter analyze` | 0 errors, 0 warnings, 2 pre-existing `info` |
| Django `manage.py test` | **79/79 passed** |

New Flutter tests: session display-name restore, 401→banner→logout→clear,
stale-error clearing on retry, login-screen banner (widget), submit retry
recovers / timeout surfaced, Edit button gating + edit flow + cancel, card
coordinate layout. New Django tests: upload guard (tiny + pixel-bomb rejected),
server flags (`can_delete`/`can_edit` in payloads), citizen PATCH allow-list
(403 messages), auth throttle (429 after 10).

---

## D. Production verification (read-only)

- `GET https://civic-intelligence-api.onrender.com/api/issues/?limit=1` → **200**
  (Render cold start ≈ 30–60 s on free tier).
- `GET .../api/issues/21/` → 200, but the payload does **NOT** contain
  `can_delete` / `can_edit`. **The new backend is not deployed.** Consequences
  until a redeploy:
  - Edit/Delete buttons stay hidden in the new client for all reports
    (defensive fallback — consistent, not broken);
  - the 10-minute delete-window 403 and the auth rate limit are not enforced;
  - submission de-dup (migration 0005) is not active.
- Durable media: media is served from Render's ephemeral disk — **R2/S3
  durable storage is still not configured**.

---

## E. Deployment checklist (Render)

1. Push the repository to GitHub `main` (the `civic-intelligence-api` service
   deploys from GitHub, Docker runtime, `rootDir: backend`).
2. The Dockerfile already runs `migrate` → `collectstatic` → `gunicorn` on
   boot, which will apply `0005_client_request_id` (additive, safe) and the new
   code. **Uninstall/removal of anything is not part of this change.**
3. Optional env: `AUTH_THROTTLE_RATE` (default `10/min`). Keep `SECRET_KEY`,
   `SECURE_SSL_REDIRECT`, HSTS, CORS/CSRF and `ALLOWED_HOSTS` as-is.
4. Post-deploy verification (against live HTTPS):
   - `GET /api/issues/{id}/` includes `can_delete` + `can_edit`;
   - citizen `PATCH {"latitude": ...}` → 403; `PATCH {"description": ...}` → 200;
   - `DELETE` of a >10-min-old own report → 403 with the window message;
   - 11 rapid logins from one IP → 11th is HTTP 429.

---

## F. Release artifact decision (APK)

Existing verified release (unchanged, still valid):
- `C:\Users\SUJAL\Downloads\FixMyGrid.apk` (source
  `release\FixMyGrid.apk`) — SHA-256
  `D0CB7A722EBE978D2A64266FB81693EE0C5EC7CC95229C90D75`, versionName
  **1.0.1**, versionCode **2**, appId `com.civicintelligence.civic_intelligence`,
  API base `https://civic-intelligence-api.onrender.com`.

**Decision: do NOT build a new APK yet.** The verified APK is the correct
artifact for the currently-live backend. The new client is designed against the
new backend (server flags, allow-listed edits, window semantics) and must be
paired with the redeployed API.

When the backend is live, the new build path is:
1. `flutter test` + `flutter analyze` (must stay green).
2. `flutter build apk --release`.
3. Sign with the release key (as the existing artifact), then report: path,
   versionName/versionCode, appId, SHA-256 (via
   `Get-FileHash`), `apksigner` signer, embedded base URL (scan `libapp.so` for
   `onrender.com` and confirm no LAN/`10.0.2.2`/`127.0.0.1` refs).
4. Two-account on-device smoke test (§G), then distribute.

---

## G. Phase 15 — on-device verification (planned, not yet run)

Device `ZD2224MKS4` (motorola edge 20 fusion), build-tools
`C:\Android\Sdk\build-tools\36.0.0\`, prod test account
`finaldemo20260923x@example.com` / `Demo@1234`. Run after the redeploy + new
APK: two-account report → edit (description/address while editable) → delete
within 10 min → confirm Edit/Delete disappear after the window → confirm
session-expiry banner after a revoked token.

---

## H. Known limitations / follow-ups

- **Backend not deployed** (this pass added code + tests only) — deploy before
  relying on the new flags/limits.
- R2/durable media storage not configured (free-tier ephemeral disk).
- Layout heuristics (height/position of action rows, banner styling) verified by
  widget tests; final polish on a real device is in §G.

## I. Production-safety confirmation

No destructive migrations, no secrets added, no auth/authorization weakened,
no demo bypasses or fake responses; the citizen PATCH allow-list *tightens*
privileges; rate limiting adds an anonymous-traffic guard; all new behavior is
covered by automated tests before any deploy.