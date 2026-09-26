# Civic Intelligence (FixMyGrid)

A civic-intelligence platform that turns citizen-reported urban problems
(potholes, garbage, broken streetlights, drainage, …) into structured,
de-duplicated, prioritized and department-routed actions for local
authorities — using **honest, deterministic, explainable rules** rather than
untrained black-box "AI" claims.

Version **1.2.0** — Flutter mobile app + Django REST backend + light authority
web dashboard + optional FastAPI AI sidecar.

> **Read this first — what this project is and is not.**
> - The civic-intelligence layer is a **rule-based engine** (GPS proximity,
>   category match, text overlap, perceptual image hashing). It is auditable,
>   deterministic and reproducible. It is **not** a trained ML model, and we do
>   **not** claim computer-vision detection, LLM understanding or learned
>   embeddings. See [docs/ai.md](docs/ai.md).
> - The mobile UI reports the engine's outputs honestly: "*Similarity to
>   existing reports*" (not "confidence") and an "*Explainable priority*" with
>   per-factor reasons. See [docs/duplicate-intelligence.md](docs/duplicate-intelligence.md).

## Repository layout

```text
backend/       Django + DRF API and the rule-based civic engine
lib/           Flutter app (citizen + my-reports + map + profile)
authority-web/  Authority Admin: React + TypeScript + Vite SPA (login, dashboard,
                issues list/detail, map, analytics) served as a static site
integration_test/  On-device E2E (self-contained two-account, network failure)
test/          Widget/unit tests for the Flutter app
docs/          Honest technical documentation + claim sheet
release/       Signed release artifacts + hardening report
```

## What is implemented (v1.2.0)

| Capability | Where | Evidence |
| --- | --- | --- |
| Citizen reporting (photo + location + category) | Flutter + `POST /api/issues/` | E2E, 171 Flutter tests |
| Duplicate intelligence v3 (GPS + category + text + image + embedding), cluster master/supporting model | `backend/issues/civic.py` | 113 Django tests |
| Explainable priority 0–100 with reasons | `civic.py::score_priority` | tests + unit suite |
| Severity + department routing | `civic.py` | tests |
| Hotspots (public + authority heat-map cells) | `/api/hotspots/`, `/api/authority/hotspots/` | IMPLEMENTED — re-verify live after redeploy |
| Collapsed public feed (master issues; `?collapse=0` for all) | `issues/views.py` | tests |
| My Reports isolation, edit/delete gated by server flags | serializers `can_edit`/`can_delete` | E2E |
| Idempotent submission (`client_request_id`), 10-min delete window | `issues/views.py` | tests |
| Resolution verification (honest BEFORE/AFTER image similarity) | `civic.py::image_similarity` | tests |
| Dark mode + system appearance | Flutter `appearance_provider` | tests |
| Vision/AI transparency (real YOLOv8n COCO, CNN embeddings, advisory ML priority, exact model provenance) | `ai_service/` + issue `vision` field | 9 AI tests; `docs/ai.md` |
| E2E suites that self-register accounts and leave zero leftovers | `integration_test/` | on-device |

## Become honest — our claim sheet

Every claim in this repository is backed by evidence or marked PARTIAL /
BLOCKED. See **[docs/claim-sheet.md](docs/claim-sheet.md)** for the full
claim-vs-evidence matrix, and **docs/security.md** for what we deliberately do
*not* do (no stored credentials, no fake metrics, secret-scan before commit).

## Quick start

### Backend (local)

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
copy .env.example .env        # set SECRET_KEY, DEBUG=True for local
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver    # http://127.0.0.1:8000
python manage.py test         # 113 tests (4 PostGIS SKIP on non-GIS DB)
```

### Mobile

```powershell
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter test                  # 171 tests
```

### E2E on a device (needs the production backend running)

```powershell
flutter test integration_test/two_account_e2e_test.dart -d <device>
flutter test integration_test/network_failure_e2e_test.dart -d <device>
```

Both suites self-register throwaway accounts at runtime and leave **zero**
reports in the shared database when they finish.

## Deployment

Production (Render):

| Service | URL | Notes |
| --- | --- | --- |
| Django API | https://civic-intelligence-api.onrender.com | Docker, `backend/`, health check `/api/health/` |
| Authority Admin | https://civic-intelligence-authority.onrender.com | static site, `authority-web/`, `/index.html` rewrite |

Both services are defined in [render.yaml](render.yaml) and deploy from
`main` of this repository. The Admin is a browser SPA that calls **only** the
Django API; the Citizen app and the Admin never talk to each other.

`VITE_API_BASE_URL` is **pinned at build time** to the public API in
`render.yaml`, so the built bundle can never point at `localhost`. Because Vite
inlines `VITE_*` variables during `npm run build`, changing the API host means
rebuilding the Admin, not just restarting it.

CORS is explicit and locked down: `CORS_ALLOW_ALL_ORIGINS=False` and
`CORS_ALLOWED_ORIGINS` lists only the API's own origin plus the real Admin
hostname (scheme + host, no path, no wildcard). Django reads this at process
start, so changing it requires an API redeploy.

The API deploys to Render via Docker. See [docs/deployment.md](docs/deployment.md)
for env vars, the migration-on-boot command, and the honest list of what is
blocked (PostGIS, S3/R2 media) and the non-GIS solutions in place.

The optional `ai_service` sidecar is a **separate, paid** service and is not
part of the demo deployment. With it unset, `AI_SERVICE_URL` is empty and the
API reports vision honestly as `{"status": "not_analyzed", "service": null}`
while duplicate intelligence still runs on the deterministic rule engine.

## Documentation

- [docs/architecture.md](docs/architecture.md) — real system architecture
- [docs/ai.md](docs/ai.md) — what "AI" means here (and what it does not)
- [docs/duplicate-intelligence.md](docs/duplicate-intelligence.md) — the v2 dedup engine
- [docs/api.md](docs/api.md) — endpoint reference
- [docs/deployment.md](docs/deployment.md) — Render deploy + env vars
- [docs/testing.md](docs/testing.md) — test suites and how to run them
- [docs/security.md](docs/security.md) — auth/isolation/limits + secret policy
- [docs/demo.md](docs/demo.md) — running the demo (no shared demo accounts)
- [docs/claim-sheet.md](docs/claim-sheet.md) — claim vs evidence matrix

## License / disclaimer

Hackathon-stage prototype demonstrating the concept and technical feasibility
of honest civic intelligence. Statistics cited in project notes come from
public government sources and describe the civic problems the platform
addresses; nothing here claims those outcomes are prevented by this software.

**Report less. Understand more. Act faster.**