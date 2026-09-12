# Civic Intelligence — Final Release Report (v1.0.0+1)

Generated: 2026-09-13

## A. Status
**DEPLOYED AND LIVE.** Backend + managed Postgres running on Render (free tier);
signed APK/AAB built against the real HTTPS URL; end-to-end smoke tests pass
against production. Only optional extras remain (Play Store account, real-device
E2E re-run).

## B. Production API URL
**https://civic-intelligence-api.onrender.com** (verified: `GET /api/health/` →
`{"status":"ok"}`, `GET /api/issues/` → 200).
- App in `release/CivicIntelligence.apk` / `CivicIntelligence.aab` points at this
  URL (embedded, verified in `libapp.so` — no LAN/emulator IPs remain).

## C. APK
- `release/CivicIntelligence.apk` (52.7 MB) — **PRODUCTION build (signed with the
  release key)**, points at `https://civic-intelligence-api.onrender.com`.
  Signer verified via `apksigner`: `CN=Civic Intelligence`; binary scan confirms
  the production URL is embedded and no `192.168.x`/`10.0.2.2`/`127.0.0.1` refs
  exist in `libapp.so`.
- `release/CivicIntelligence-local-demo.apk` (52.7 MB) — earlier LAN demo build
  (points at `http://192.168.1.8:8000`), kept for offline/demo use only.

## D. AAB
- `release/CivicIntelligence.aab` (51.5 MB) — **PRODUCTION Play-Store upload
  candidate** (same production URL, signed with the release key).
- `release/CivicIntelligence-app-release.aab` — earlier LAN demo AAB.

## E. Version
- `1.0.0+1` (versionName 1.0.0, versionCode 1), package
  `com.civicintelligence.civic_intelligence`.

## F. Test results
- Django backend: **37/37** passed.
- Flutter analyze: **0 issues**; Flutter tests: **118/118** passed.
- Production smoke (live HTTPS, 2026-09-13): register (201) → login (200) →
  create issue with photo (201, category pothole, severity low, routed to
  **Road Maintenance**) → `GET /api/my-reports/` returns the submitted issue
  with served `image_url` → all 200.
- Production config: `check --deploy` warnings resolved at deploy (long random
  `SECRET_KEY`, `SECURE_SSL_REDIRECT=True`, HSTS enabled via env, CORS/CSRF
  locked to the onrender.com origin, `ALLOWED_HOSTS=.onrender.com`).

## G. Deployment (live)
- Render web service `civic-intelligence-api` (id `srv-dairo2oae00c73fmop20`),
  Docker runtime, rootDir `backend`, deploy from GitHub main.
- Render Postgres `civic-intelligence-db` (id `dpg-daireu9594qs739td79g-a`,
  v16, free/oregon) — `civic_intelligence` DB wired via env.
- `backend/Dockerfile` runs migrate + collectstatic + gunicorn on boot.
- `render.yaml` blueprint kept in repo; service provisioned via Render CLI.
- Free-tier caveats: data/media lives on an ephemeral disk — durable media
  storage (S3/R2 or a Render disk) is a recommended follow-up; single instance.

## H. Signing
- Release keystore: `android/app/upload-keystore.jks` + `android/key.properties`
  (both gitignored); **backup in `release/private/` — keep safe, never
  commit/share.** Password stored only in `key.properties` (never printed).
- `android/app/build.gradle.kts` release-signs; debug-key fallback only when
  `key.properties` is absent.

## I. Remaining manual/optional actions
1. **Real-device E2E re-run** with the production APK: connect the phone
   (USB debugging) and I'll run `integration_test/app_e2e_test.dart` against the
   live URL. Since this needs a physical device it couldn't be automated here.
2. **Security housekeeping (rec.)**: rotate the Render Postgres password and the
   GitHub PATs that were pasted into this session's chat; the DB is fresh and
   used only by this project, so risk is low.
3. **Play Store**: create a Play Console account ($25, human verification) and
   upload `CivicIntelligence.aab`. Not done — requires the account holder.
4. GitHub Release for `release/CivicIntelligence.apk` when you want to share it.

## J. Demo instructions
- Public app: install `release/CivicIntelligence.apk` anywhere — it talks to the
  live backend. Register → report an issue with a photo → follow the rule-based
  analysis (severity, department routing, duplicates).
- Local demo (offline): `backend\.venv\Scripts\python.exe backend\manage.py
  runserver 0.0.0.0:8000` + `release/CivicIntelligence-local-demo.apk` on the
  same LAN. Staff console: `createsuperuser` → `/authority/`.

## K. Final verdict
Complete and live: code green, tests green, signed production artifacts built
against the real HTTPS URL, deploy verified end-to-end with real requests.
Production URL is real and reachable (not fabricated).