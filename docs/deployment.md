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