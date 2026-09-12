# Civic Intelligence — Production Deployment

## Single manual step
The codebase is production-ready and **release signing is already provisioned**,
but **deployment requires a hosting account and your own production
URLs/credentials** — this cannot be automated for you.

Pick one of:
- Render / Railway / Fly.io for the Django web service (+ managed PostgreSQL).
- A domain (e.g. `api.example.com`) pointed at the service.

## Then deploy

1. **Render (one-click):** a `render.yaml` blueprint and `backend/Dockerfile`
   are included. In the Render dashboard: *New → Blueprint* → select this repo.
   Fill the `sync: false` env values (your domain + Postgres credentials) shown
   in the blueprint. The container runs migrate + collectstatic + gunicorn on
   boot; health checks poll `/api/health/`.
2. **Any platform / manual:** point the service at the `backend/` folder and
   set the env vars from `backend/.env.production.example`:
   - `SECRET_KEY` (generate: `python -c "import secrets; print(secrets.token_urlsafe(64))"`)
   - `DEBUG=False`
   - `ALLOWED_HOSTS=<your-domain>`
   - `DB_ENGINE=postgresql` + `DB_*` values
   - `SECURE_SSL_REDIRECT=True`
   - `SECURE_HSTS_SECONDS=31536000` (optional, after HTTPS is confirmed)
   - `CSRF_TRUSTED_ORIGINS=https://<your-domain>`
   - `CORS_ALLOW_ALL_ORIGINS=False`, `CORS_ALLOWED_ORIGINS=https://<your-domain>`
3. Databases: create a Postgres database and ensure `DB_*` point at it.
   (SQLite is used only when `DB_ENGINE` is unset.)
4. Verify: `curl https://<your-domain>/api/health/` → `{"status":"ok"}`.
5. Uploaded media: add a persistent volume for `/app/media` (or switch to an
   S3-compatible storage).
6. **Build the FINAL production APK/AAB against the LIVE HTTPS URL** (release
   builds are signed with the release key in `android/key.properties`):
   ```
   release\scripts\build-production.ps1 -ApiUrl https://<your-domain>
   ```
   This writes `release\CivicIntelligence.apk` and `release\CivicIntelligence.aab`.
7. Before store submission: back up the keystore
   (`android/app/upload-keystore.jks` + `android/key.properties`, also in
   `release/private/` — never commit or share either; the password is stored
   only in `key.properties`).

## Signing (already done)
- `android/app/upload-keystore.jks` + `android/key.properties` generated and
  gitignored; `build.gradle.kts` signs release builds with them (falls back to
  the debug key only if `key.properties` is missing).
- Public-data only: alias `upload`, RSA 2048, validity 10000 days.
  **Back up `release/private/` — the upload key is irrecoverable if lost.**

## Hardening already in place
- SECRET_KEY/DEBUG/ALLOWED_HOSTS env-gated; production refuses to boot without
  a key when DEBUG=False.
- CORS locked to explicit origins; cookie security on; X-Forwarded-Proto trust;
  env-gated HSTS (`SECURE_HSTS_SECONDS`).
- Staff-only authority endpoints (IsAdminUser) and staff-only dashboard.
- Reporter writes limited to own-report fields; lifecycle is authority-owned
  and transition-validated; resolution requires BEFORE/AFTER evidence.
- `GET /api/health/` public health endpoint for load-balancer checks.
- whitenoise serves staticfiles; gunicorn workers configured in Procfile.