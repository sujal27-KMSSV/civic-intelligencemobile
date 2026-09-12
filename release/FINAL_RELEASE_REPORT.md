# Civic Intelligence — Final Release Report (v1.0.0+1)

Generated: 2026-09-13

## A. Status
**READY FOR RELEASE — PRODUCTION DEPLOYMENT PENDING ONE MANUAL ACTION**
All local engineering, security, signing, and test gates pass. The only remaining
step is creating a hosting account + domain (and optional Google Play account),
which requires human credentials/verification and cannot be automated.

## B. Production API URL
**None yet.** No public URL exists and none was invented. See section J for the
exact steps to obtain one (hosting account → `build-production.ps1` → real URL).
The shipped demo APK points at a LAN backend for judging/demo only.

## C. APK
- `release/CivicIntelligence.apk` — **NOT BUILT YET**; produced by
  `release\scripts\build-production.ps1 -ApiUrl https://<your-domain>`
  against the live HTTPS URL (signed with the release key).
- `release/CivicIntelligence-local-demo.apk` (52.7 MB) — signed with the release
  key, points at `http://192.168.1.8:8000` (LAN demo only). Signer confirmed via
  `apksigner`: `CN=Civic Intelligence, ...`.

## D. AAB
- `release/CivicIntelligence.aab` — **NOT BUILT YET**; produced by the same
  command as section C (Play Store upload candidate).
- `release/CivicIntelligence-app-release.aab` (51.5 MB) — signed demo AAB (LAN).

## E. Version
- `1.0.0+1` (versionName 1.0.0, versionCode 1), package
  `com.civicintelligence.civic_intelligence`.

## F. Test results
- Django backend: **37/37** passed.
- Flutter analyze: **0 issues**.
- Flutter widget/integration-safe tests: **118/118** passed.
- On-device E2E (prior session, signed build): register → list → login → submit
  report (201, analysis payload) → my-reports → media all 200 against live backend.
- Production config dry-run: `manage.py check --deploy` → warnings only
  (HSTS/SSL-redirect to be enabled at deploy via env); `collectstatic` OK (157
  files). `GET /api/health/` → `{"status":"ok"}` on the running server.

## G. Deployment
- **Not deployed (single manual blocker).** Everything else is pre-staged:
  - `backend/Dockerfile` (migrate + collectstatic + gunicorn on boot)
  - `render.yaml` Render blueprint (web service, `SECRET_KEY` auto-generated,
    Postgres env wiring, `/api/health/` checks)
  - `backend/.env.production.example` (full env template)
  - `Procfile` + `runtime.txt` (python-3.14) for platform deployments
  - HSTS env-gated; SSL redirect, cookie-security, CORS locked, staff-only
    authority endpoints.

## H. Signing
- Release keystore generated (RSA 2048, alias `upload`, 10000-day validity):
  - `android/app/upload-keystore.jks` + `android/key.properties` (gitignored)
  - **Backup: `release/private/` (copy moved here — keep safe, never commit/share)**
  - Password is stored ONLY in `key.properties`; it was never printed anywhere.
- `android/app/build.gradle.kts` signs release builds with this key; it falls
  back to the debug key only if `key.properties` is absent (dev convenience).
- If you change your mind on the password, regenerate before any Play upload.

## I. Remaining manual actions (only these)
1. **Create a hosting account (Render/Railway/Fly) + optional domain** and
   a managed PostgreSQL DB. Render: New → Blueprint → this repo -> fill env
   values (`ALLOWED_HOSTS`, `DB_*`, `CORS_*`, `CSRF_TRUSTED_ORIGINS`).
2. Verify `curl https://<your-domain>/api/health/` → `{"status":"ok"}`.
3. Build the real release APK/AAB:
   `release\scripts\build-production.ps1 -ApiUrl https://<your-domain>`.
4. (Optional) Play Store: create a Play Console developer account ($25) and
   upload `CivicIntelligence.aab` under this signing key. This was NOT done.
5. (Optional) GitHub: initialize the repo and open a GitHub Release to share the
   production APK. `gh`/git remote are not configured on this machine.

## J. Demo instructions (until hosted)
1. Start backend: `backend\.venv\Scripts\python.exe backend\manage.py runserver 0.0.0.0:8000`
2. Install `release/CivicIntelligence-local-demo.apk` on an Android device on
   the same LAN (app is pre-pointed at `http://192.168.1.8:8000` — adjust the
   dart-define + rebuild only if that IP differs).
3. Register → submit a civic report → watch rule-based analysis (severity,
   department routing, duplicate detection), then sign in as staff
   (`createsuperuser`) and open `/authority/` to review/report/resolve.

## K. Final verdict
Code, security, signing, tests, and release tooling are complete and green.
**The project is release-ready; a human account + domain are the only
prerequisite to going public (no URL was fabricated).**