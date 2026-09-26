# Deployment

The API deploys to **Render** as a Docker web service. On every push to GitHub
`main`, Render rebuilds and re-runs the migration + collectstatic sequence
from the Dockerfile before starting gunicorn.

## Build & boot (`backend/Dockerfile`)

```text
FROM python:3.14-slim
pip install -r requirements.txt
CMD migrate --noinput && collectstatic --noinput && gunicorn config.wsgi --bind 0.0.0.0:$PORT --workers 3 --timeout 120
```

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
| `API_BASE_URL` (Flutter build) | `--dart-define=API_BASE_URL=https://civic-intelligence-api.onrender.com` |

## Post-deploy verification

```text
GET /api/health/                                 -> {"status":"ok"}
GET /api/issues/?limit=1                         -> 200, flattened payload
GET /api/issues/                                 -> masters only (collapse default)
GET /api/hotspots/                               -> 200, cells array
GET /api/authority/hotspots/   (staff)           -> 200
python manage.py showmigrations issues           -> 0006 applied
```

## Known production constraints (honest)

- **Cold start:** free tier can take seconds; first request may time out.
  Do not weaken the client timeouts to "fix" this; retry is built into the app.
- **PostGIS — BLOCKED.** Render's free Postgres has no PostGIS extension and
  the repo does not bundle GDAL. Spatial work is non-GIS: bounding box +
  haversine + grid bucketing. No claim of PostGIS is made anywhere.
- **S3/R2 media — BLOCKED (no credentials).** `MEDIA_STORAGE_BACKEND=s3` and
  `django-storages[boto3]` are wired but unexercised; media lives on the
  instance disk in dev/demo. Durable off-instance storage is the documented
  next step once credentials exist.
- **Migrations** `0006` add the priority/cluster/image-feature columns; the
  server applies them on boot, existing rows keep `priority = 0` until a new
  analysis touches them (new submissions/matches always compute priority).