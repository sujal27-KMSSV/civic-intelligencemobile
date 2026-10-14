# Deployment

The API deploys to **Render** as a Docker web service. On every push to GitHub
`main`, Render rebuilds and re-runs the migration + collectstatic sequence
from the Dockerfile before starting gunicorn. The optional FastAPI AI sidecar
is a *separate* service that Django calls over an internal URL.

## Build & boot (`backend/Dockerfile`)

```text
FROM python:3.14-slim
pip install -r requirements.txt
CMD migrate --noinput && collectstatic --noinput && gunicorn config.wsgi --bind 0.0.0.0:$PORT --workers 3 --timeout 120
```

## AI sidecar (`ai_service/Dockerfile`) — separate service

```text
FROM python:3.14-slim          # need system libgomp for torch CPU
pip install -r ai_service/requirements.txt
CMD uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Then set Django's `AI_SERVICE_URL=https://<ai-service-url>` (e.g. across two
Render services). **Honest constraint: Render's free tier (512 MB RAM) cannot
run torch** — the sidecar document targets grow/pay tiers or a small VPS. On
startup it downloads the pinned weights and warms models lazily.

## Environment (see `render.yaml`, `backend/.env.example`)

| Variable | Notes |
| --- | --- |
| `DEBUG` | must be `False` in prod (guard requires `SECRET_KEY`) |
| `SECRET_KEY` | Render `generateValue: true`; never in VCS |
| `ALLOWED_HOSTS` | prod domain(s); local default `"*"` only for dev |
| `DB_ENGINE`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`/`DB_HOST`/`DB_PORT` | managed Postgres for prod; SQLite locally |
| `DB_SSLMODE` | `require` for external managed Postgres (Neon/Supabase/Aiven); unset for a same-network Render DB |
| `DB_CHANNEL_BINDING` | optional libpq channel binding (Neon may ask for `require`) |
| `DB_CONN_MAX_AGE` / `DB_CONNECT_TIMEOUT` | seconds; reuse TLS connections (keep below the provider's idle-suspend window) and bound the initial connect wait |
| `SECURE_SSL_REDIRECT`/`SECURE_HSTS_SECONDS` | `True` / 31536000 in prod |
| `CSRF_TRUSTED_ORIGINS`, `CORS_ALLOWED_ORIGINS` | set explicitly in prod |
| `MEDIA_STORAGE_BACKEND` | `local` (default) or `s3` (unused until creds exist) |
| `AI_SERVICE_URL` / `AI_SERVICE_TIMEOUT` | sidecar URL; empty = rule-based only |
| `GEOSPAT_ENABLED` | only with `DB_ENGINE=postgresql` + a PostGIS-capable DB (`docs/postgis.md`) |
| `API_BASE_URL` (Flutter build) | `--dart-define=API_BASE_URL=https://civic-intelligence-api.onrender.com` |

## Post-deploy verification

```text
GET /api/health/                                 -> {"status":"ok"}
GET /api/issues/?limit=1                         -> 200, flattened payload
GET /api/issues/                                 -> masters only (collapse default)
GET /api/hotspots/                               -> 200, cells array
GET /api/authority/hotspots/   (staff)           -> 200
python manage.py showmigrations issues           -> 0007 applied
```

## Known production constraints (honest)

- **Cold start:** free tier sleeps after ~15 min idle and takes ~30-60s to
  boot again. The client's safe-to-retry requests (reads, auth, idempotent
  submissions) give BOTH the first attempt and the single retry a 60 s
  cold-start budget, so a sleeping instance is absorbed without the user
  seeing an error; a genuinely unreachable backend still fails cleanly after
  ~2 min with a clear retryable message (`lib/core/network/api_client.dart`).
- **PostGIS** — conditionally available. Render's *free* Postgres has no
  PostGIS extension, so `GEOSPAT_ENABLED=0` by default on the demo fleet and
  the geospat route is unmounted; on a real PostGIS DB enable it
  (`docs/postgis.md`). Spatial work elsewhere stays non-GIS: bounding box +
  haversine + grid bucketing.
- **AI service memory** — free tier (512 MB) cannot host torch; documented
  split above, and Django degrades to rule-based without it (`docs/ai.md`).
- **S3/R2 media — BLOCKED (no credentials).** `MEDIA_STORAGE_BACKEND=s3` and
  `django-storages[boto3]` are wired but unexercised; media lives on the
  instance disk in dev/demo. Durable off-instance storage is the documented
  next step once credentials exist.
- **Migrations** `0007` add the vision/embedding/priority-model columns; the
  server applies them on boot, existing rows keep those fields empty until a
  new analysis touches them (new submissions always compute them).

## Free-tier database recovery (no paid services)

**Context (2026-10):** Render's free Postgres expires **30 days after creation**
(then a 14-day grace, then deletion) and has **no backups** on free. A free DB
that expires leaves the API unable to resolve its old internal hostname
(`failed to resolve host 'dpg-…'`), so `migrate` aborts at boot and the service
never serves. Render free web services are still free — only the DB expired.

**Chosen free replacement: [Neon](https://neon.tech)** — permanent free plan,
no credit card, standard Postgres wire protocol (works with `psycopg`), 1 GB per
project, branch/restore history, and a scale-to-zero compute that wakes in
~300 ms (the client already tolerates cold starts with a 60 s budget). Supabase
free pauses after 1 week idle; Aiven free powers off when unused — both are
viable but need a manual wake, so Neon is preferred here.

**Recovery runbook (all free):**

1. **Export the old data before it is deleted.** Render free has no backups and
   no `pg_dump` button, but you can dump it from your own machine while it still
   exists using the database's **External** connection string (Render dashboard
   → the Postgres → Connections → *External Database URL*):

   ```powershell
   # $env:OLD_DB_URL = "<external connection string, keep it out of git>"
   pg_dump --no-owner --no-acl "$env:OLD_DB_URL" | Out-File -Encoding utf8 old-db.sql
   ```

   If that succeeds, restore it into the new Neon database with
   `psql "$env:NEW_DB_URL" -f old-db.sql`. **Do not claim the data was recovered
   without running this and checking the row counts.**
2. **Create the Neon project** (dashboard, no card) and copy its **pooled**
   connection details (`…-pooler.<region>.aws.neon.tech`).
3. **Point the existing Render API service at Neon** (dashboard → the
   `civic-intelligence-api` service → Environment). Change only the `DB_*`
   variables; keep every other variable as-is (there is no need to use a Render
   Blueprint, and the old service/DB is left untouched until this is verified):
   `DB_HOST` = Neon pooled host, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, keep
   `DB_PORT=5432`, add `DB_SSLMODE=require`, `DB_CONN_MAX_AGE=60`.
   Saving triggers a redeploy; the Dockerfile runs `migrate` on boot and builds
   the schema on the empty Neon DB.
4. **Verify:** `GET https://civic-intelligence-api.onrender.com/api/health/`
   returns `{"status":"ok"}`. Only then is recovery real.

The mobile app and the admin site already target
`https://civic-intelligence-api.onrender.com`, so **no APK/admin URL change is
needed** — the frozen release artifacts stay valid.

**Caveat (Render Free web service + external DB):** Render's docs warn that a
Free web service "may be suspended" if it "initiates an uncommonly high volume
of traffic over the public internet," and list *accessing an external database*
as an example. A low-traffic demo to Neon is fine, but if the service is ever
suspended for service-initiated traffic, the alternatives are: a same-region
Render Postgres (reachable over Render's private network, but its Free tier
still expires in 30 days) or moving the API to another free host. Prefer
`MEDIA_STORAGE_BACKEND=s3`/object storage only once credentials exist; media on
the instance disk is lost on every spin-down/redeploy.

## Staff admin bootstrap (hosts without a shell)

Render **Free** web services do not support Shell access, SSH, or one-off jobs
(confirmed in Render's docs), so an unattended boot step is the only no-cost way
to create the first admin there. Two options:

1. **Preferred where a shell exists** (paid Render, a VPS, locally):
   `python manage.py bootstrap_admin --email authority@example.com --superuser`.
2. **Shell-less hosts (Render Free):** set all of the following on the service,
   then deploy once:
   - `CIVIC_BOOTSTRAP_SECRET` — a strong, private, **backend-only** secret of at
     least 32 chars (`python -c "import secrets; print(secrets.token_urlsafe(48))"`).
     This *arms* the mechanism; without it the boot step does nothing.
   - `CIVIC_BOOTSTRAP_ADMIN_EMAIL` — the admin's email.
   - `CIVIC_ADMIN_PASSWORD` — the admin's password (required so nothing is
     generated or written to the logs).
   - optionally `CIVIC_BOOTSTRAP_ADMIN_SUPERUSER=1` for Django-admin access.

   The Dockerfile runs `manage.py bootstrap_admin --unattended` after `migrate`.
   That mode **refuses to run** without the strong secret, **never generates or
   logs a password**, and is **one-time**: once any staff account exists it is a
   silent no-op. It is also non-fatal — a failure cannot stop the API serving.

   **Remove `CIVIC_BOOTSTRAP_SECRET`, `CIVIC_BOOTSTRAP_ADMIN_EMAIL` and
   `CIVIC_ADMIN_PASSWORD` after the first successful boot.** Never expose a
   bootstrap endpoint or a password in frontend code.