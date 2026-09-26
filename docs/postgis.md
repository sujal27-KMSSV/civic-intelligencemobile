# PostGIS (`geospat`)

## Capability boundary (honesty contract)

PostGIS is **conditional by design**, never emulated:

- `backend/geospat/` is only registered in `INSTALLED_APPS` when the runtime
  really has PostgreSQL + PostGIS + GDAL (`DB_ENGINE=postgresql` **and**
  `GEOSPAT_ENABLED=1`).
- Without it: the app is absent, `/api/geospat/nearby/` is not routed, the
  4 integration tests `SKIP` (visible in the test runner output), and duplicate
  detection/hotspots keep running on the pure-Python haversine/grid logic.
- The free-tier Render Postgres in this project **lacks the PostGIS
  extension**, so on the current deployment the spatial route is off. That is
  stated, not papered over.

## What is implemented (genuine)

- `SpatialLocation`: one `PointField(srid=4326, geography=True)` per issue,
  giving metric (`ST_DWithin`, `ST_Distance`) semantics.
- `POST-SAVE` receiver keeps the row in sync (`geospat/apps.py::ready`).
- `GET /api/geospat/nearby/?lat=&lon=&radius_m=&limit=` — real
  `ST_DWithin` neighbourhood search of **open** issues, annotated with
  `ST_Distance`, ordered by distance.
- `python manage.py geospat_sync` — idempotent backfill of historical issues.
- Hand-written migration `geospat/migrations/0001_initial.py` (only applies on
  a PostGIS backend).

## Why migrations are hand-written

`makemigrations` can only emit GeoDjango migrations on a machine that actually
has GDAL + PostGIS. Since none of the build machines here do, the (standard,
stable) migration is committed by hand so that a genuine PostGIS fleet applies
it cleanly.

## Enable on a real fleet

```env
DB_ENGINE=postgresql
POSTGRES_DB=/host...
GEOSPAT_ENABLED=1
```

Then:

```
pip install psycopg[binary]
python manage.py migrate            # applies 0001_initial
python manage.py geospat_sync       # backfill
python manage.py test geospat       # integration suite now runs, not skips
```

## Test status (this session)

`python manage.py test` → **113 OK (skipped=4)** — the 4 skips are exactly the
PostGIS integration tests, because no genuine spatial database is present in
the build/test environment. Every non-spatial helper is covered regardless.