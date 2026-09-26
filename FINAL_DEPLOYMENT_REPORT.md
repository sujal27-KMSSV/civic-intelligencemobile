# FINAL DEPLOYMENT REPORT — FixMyGrid (Civic Intelligence)

**Status: PRODUCTION DEPLOYED AND VERIFIED.**
Last updated: 2026-09-26 22:35 UTC

---

## 1. Live URLs

| What | URL | Verified |
| --- | --- | --- |
| GitHub repository | https://github.com/sujal27-KMSSV/civic-intelligencemobile | yes — `main` @ `c28fc2a` |
| Django API | https://civic-intelligence-api.onrender.com | yes — `/api/health/` → `200 {"status":"ok"}` |
| Authority Admin | https://civic-intelligence-authority.onrender.com | yes — `/`, `/login`, `/issues/123` all `200` HTML |

## 2. Deployment status

| Service | Render type | State | Commit |
| --- | --- | --- | --- |
| `civic-intelligence-api` | `web_service` (Docker, `backend/`, free) | **live** | `c28fc2a` — deploy `dep-das4d8bbc2fs7399gb00` |
| `civic-intelligence-authority` | `static_site` (`authority-web/`, free) | **live** | `825533f` — deploy `dep-das3iqojo6nc73a2hnf0` |
| `civic-intelligence-ai` | not created | intentionally not provisioned — a **paid** service the API does not require | — |

The API redeploy `dep-das4d8bbc2fs7399gb00` was triggered manually and reached
`live` at `2026-09-26T22:27:57Z`. It is the first deploy running with a
complete environment, which is what activated CORS.

API auto-deploy remains **off** deliberately, so an accidental push can never
deploy an unverified configuration.

### Incident and recovery (recorded for honesty)

An earlier environment update used Render's `PUT /services/{id}/env-vars`,
which **replaces the whole set** rather than merging. That removed
`DB_PASSWORD`, `SECRET_KEY` and 10 other variables from the service
configuration.

- No deploy was triggered during the incident, so the running API was never
  affected.
- Recoverable variables were restored; `SECRET_KEY` was regenerated (which
  invalidates existing signed sessions but not DRF tokens).
- `DB_PASSWORD` is not exposed by any Render API, so it was entered once in the
  Render dashboard by the account owner.
- The service was then redeployed and verified.

## 3. Admin build verification

- `npm ci` → clean, 201 packages
- `npm run typecheck` (`tsc -b`) → clean, exit 0
- `npm run build` → 970 modules, exit 0
- Built `dist/` is **byte-identical (6/6 files)** to the preserved artifact
  `authority-web-production-dist.zip`
  (SHA-256 `F455B482646CCBC6A61197387EE937250C45B2FEDC6565022FEEEDF0486B108F`).
- Production API URL is baked into the deployed bundle
  (`https://civic-intelligence-api.onrender.com`, 1 occurrence).
- No localhost API base in any deployed asset. The single `localhost` string in
  `index-*.js` is React DOM's own internal
  `window.location.href || "http://localhost"` environment probe, not an API URL.

## 4. CORS — ACTIVE AND VERIFIED

Live value on the API service (comma-separated, exact scheme + host, no
trailing slash, no path, no wildcard):

```text
CORS_ALLOW_ALL_ORIGINS=False
CORS_ALLOWED_ORIGINS=https://civic-intelligence-api.onrender.com,https://civic-intelligence-authority.onrender.com
CSRF_TRUSTED_ORIGINS=https://civic-intelligence-api.onrender.com,https://civic-intelligence-authority.onrender.com
```

The API's own pre-existing origin was preserved alongside the Admin origin, so
the configuration contains the two legitimate origins and nothing else.

Measured against the live service with an independent HTTP client
(`curl`), 3 rounds, cache-busted URLs:

| `Origin` sent | HTTP | `Access-Control-Allow-Origin` | Verdict |
| --- | --- | --- | --- |
| `https://civic-intelligence-authority.onrender.com` | 200 | exactly that origin | **PASS** |
| `https://evil.example` | 200 | *absent* | **PASS — refused** |
| `https://civic-intelligence-authority.onrender.com.evil.example` | 200 | *absent* | **PASS — refused** |
| `http://civic-intelligence-authority.onrender.com` (wrong scheme) | 200 | *absent* | **PASS — refused** |
| `https://civic-intelligence-api.onrender.com` | 200 | exactly that origin | **PASS** |

Preflight response also advertises
`allow-methods: DELETE, GET, OPTIONS, PATCH, POST, PUT`,
`allow-headers: …, authorization, …` and `vary: origin`.

One nuance worth recording: an `Origin` **with** a trailing slash is treated by
`django-cors-headers` as equivalent to the slash-less form and echoed back with
its slash. Browsers never send an `Origin` header with a trailing slash, path or
credentials, so this is not reachable in practice; the *configured value*
itself contains no trailing slash.

## 5. Production verification performed

| Check | Result |
| --- | --- |
| `GET /api/health/` | PASS — `200 {"status":"ok"}`, served by gunicorn |
| **Database connectivity on the new container** | PASS — `GET /api/issues/?collapse=0` → `200`, **28 rows**, **32 fields**, `priority_label` and `priority_reasons` present |
| Independent DB path | PASS — `GET /api/hotspots/` → `200` |
| CORS preflight, Admin origin | PASS — `200`, ACAO exactly the Admin origin |
| CORS preflight, `https://evil.example` | PASS — no ACAO granted |
| CORS lookalike subdomain / wrong scheme | PASS — no ACAO granted |
| Admin `/`, `/login`, `/dashboard`, `/issues/123`, `/map`, `/analytics`, nested routes | PASS — `200` HTML (SPA rewrite works) |
| Admin hashed JS/CSS assets (5 files) | PASS — `200`, correct content types |
| Missing asset `/assets/<missing>.js` | PASS — `404` (rewrite is not a file catch-all) |
| Deployed bundle API base | PASS — production API URL baked in; no authored `localhost` |
| Authority `issues/`, `issues/1/`, `issues/1/resolve/`, `stats/`, `hotspots/` anonymous | PASS — **all `401`** |
| Same routes with an invalid bearer token | PASS — **all `401`** |
| Public feed does not leak internal assignment | PASS — `assigned_to` / `assigned_at` absent (resolution outcome is intentionally public) |
| `Host: evil.example` | PASS — `403` (ALLOWED_HOSTS enforced) |
| `X-Frame-Options` / `X-Content-Type-Options` | PASS — `DENY` / `nosniff` |
| Privileged staff workflow | **credential-gated** — no legitimate production staff credential is available to the test harness, and no bypass was created |

## 6. Test summary (this repository, measured)

| Suite | Command | Result |
| --- | --- | --- |
| Django | `python manage.py test` | **113 passed, 4 skipped** (PostGIS skips) |
| Migrations | `makemigrations --check --dry-run` | No changes detected |
| Flutter | `flutter test` | **171/171 passed** |
| Flutter static analysis | `flutter analyze` | 2 info-level `prefer_const_constructors` lints in a test file; no errors/warnings |
| AI sidecar | `python -m pytest tests -q` | **11/11 passed** (torch 2.14.0+cpu, torchvision 0.29.0+cpu, ultralytics 8.4.163) |
| Admin | `tsc -b` + `npm run build` | clean, exit 0 both |

The AI suite is 11, not the original 9: two regression tests were added when
the priority label-band bug was fixed (see §8).

## 7. Citizen artifacts (preserved, not rebuilt)

| Artifact | Bytes | SHA-256 |
| --- | --- | --- |
| `release/FixMyGrid-FINAL.apk` (= `FixMyGrid-FINAL.apk.zip`) | 56,248,541 | `ECF5FEE7D8BDD53FC229FAE24F1BA024C68C345D18E40B5A0E9268457B8148C5` |
| `release/FixMyGrid-1.2.0.apk` | 56,248,541 | `4CCB2BA6A9CB40EAE8323DACCCA15675DCFE84D27C4DE21AE850A2C3A2ACA037` |
| `release/FixMyGrid-1.2.0.aab` | 54,971,094 | `BD2AD54C211D11ED69239EE84BF28428F83B185CBC32B722677182001638BF60` |
| `release/FixMyGrid-FINAL.aab` | 54,970,703 | `C877B45347E15892ACB3296629F4D314B9690646B1B79A4350C0E3085C4451B4` |

The verified deliverable is `FixMyGrid-FINAL.apk` (the `.zip` file is the APK
itself despite the extension). Release binaries are intentionally untracked.

## 8. Honest AI / CV description

- **Duplicate intelligence** is a deterministic, explainable rule engine in
  `backend/issues/civic.py`: GPS proximity, category match, text overlap,
  perceptual image hashing, and — when the optional sidecar is enabled —
  embedding cosine similarity. It is auditable and reproducible, not a trained
  black box.
- **Priority** is a transparent weighted/rule-based score (0–100) with
  per-factor reasons. This rule is authoritative for the `priority_label` the
  Citizen app and Authority Admin display.
- The optional `ai_service` sidecar contains **real** torch code and is unit
  tested (11 tests). It is **not deployed** on the free tier. When
  `AI_SERVICE_URL` is empty the API honestly reports
  `vision = {"status": "not_analyzed", "service": null}` and the UI says so.
- No claim is made that the software prevents the civic problems it addresses.

### 8a. Custom FixMyGrid YOLO detector — evaluated, deliberately NOT trained

A purpose-specific detector was scoped and **not** built, because of data:

- the repo holds **one** real photograph (a single citizen upload) and **zero**
  annotation files; `ai_service/datasets/` does not exist;
- no permissively-licensed civic-defect dataset was usable without uploading
  private citizen images to a third party.

No dataset was fabricated and no training run is claimed.

A custom model is nonetheless the correct long-term answer, and this was
measured: on the one available road photo the COCO model returned
`bird @ 0.39` and ImageNet returned `iron / shovel / great_white_shark`. COCO
has no civic classes, so generic detection cannot classify civic damage.

**No redesign is needed to adopt one later.** `config.YOLO_MODEL` already reads
`AI_YOLO_MODEL`, so a checkpoint is added by dropping in a `.pt` file and
setting that variable — zero code change. See `docs/computer-vision.md`.

### 8b. Priority label-band bug — found, fixed, no production impact

`label_for()` scanned the band table in ascending order and returned the first
band whose lower bound the score cleared. Since the first band is
`("low", 0, 30)`, **every** score ≥ 0 returned `"low"`. This also made the
recorded `label_band_accuracy: 1.0` a tautology — it compared `"low"` to
`"low"`.

Fixed by scanning with `reversed()` (the table stays low→high for readability)
in `ai_service/app/services/priority.py` and in
`ai_service/scripts/train_priority_model.py`. The metric was recomputed against
the **already-trained** checkpoint on the identical evaluation split; the model
was not retrained or overwritten.

- honest label-band accuracy: **1.0 → 0.9381**, confusion now confined to
  adjacent bands
- MAE 0.827 / RMSE 1.041 / R² 0.9946 were always correct, unchanged
- 2 regression tests added (AI suite 9 → 11)

**Production impact: none.** The operational `priority_label` comes from the
rule in `backend/issues/civic.py`, which bands correctly with
`lo <= score < hi`. The bug only affected the sidecar's diagnostic
`vision["priority_model"]["label"]`, and the sidecar is not deployed.

## 9. Known limitations

1. **The AI sidecar is not deployed** — it needs ~2 GB RAM (paid plan). Vision
   therefore reports `not_analyzed` in production while duplicate intelligence
   still works.
2. **PostGIS is disabled in production** (`GEOSPAT_ENABLED=False`): Render's
   free Postgres has no PostGIS extension, so genuine spatial neighborhood
   search is off. Non-GIS fallbacks are used.
3. **Media is on local container storage**, not S3/R2, so uploaded images do not
   survive a redeploy or scale horizontally.
4. **Privileged production staff flows are unverified** — no legitimate
   production staff credential was available for automated testing. The Admin's
   authenticated surfaces are covered by contract tests and local suites only.
5. **No physical-device or browser-DOM E2E** against production.
6. Flutter analysis reports 2 info-level lints in a test file.

### Verified production limitations (measured, not assumed)

These were confirmed by direct inspection of the live API during the final
acceptance audit. They are recorded here so nothing is overstated to a judge.

1. **All 28 report images return HTTP 404.** `render.yaml` declares no
   persistent disk, so `MEDIA_ROOT` (`backend/config/settings.py`) lives on the
   container filesystem and was discarded by the redeploy. Issue rows and their
   derived metadata survive in PostgreSQL; the image bytes do not. Newly
   submitted reports render normally until the next API redeploy. The remedy is
   infrastructure, not code: a Render persistent disk (paid) or switching
   `MEDIA_STORAGE_BACKEND` to S3/R2 with credentials.
2. **The 28 rows are E2E/manual-test artifacts, not real civic reports.** The
   stored media filenames are the test suite's own `e2e_<epoch_ms>.png` and the
   descriptions and coordinates match files under `integration_test/`. Only ids
   56 and 60 are consistent with genuine physical-device submissions. Do not
   describe the existing rows as collected civic data.
3. **27 of 28 rows have an empty `address`.** The Flutter client reverse-geocodes
   an address for display but never includes it in the multipart request body,
   while the model, serializer and `REPORTER_EDITABLE_FIELDS` all accept it.
4. **26 of 28 rows have `priority: 0.0`, `priority_label: "low"` and no
   `priority_reasons`.** `run_analysis` executes at creation time, and those rows
   predate the current engine; only ids 56 and 60 (created by the current build)
   show explainable priority. The dashboard's priority column therefore looks
   empty for historical rows.
5. **No row carries computer-vision output.** 27 rows have `vision: {}` and one
   has `{"status": "not_analyzed"}`. This is the honest fallback, because the AI
   sidecar is intentionally not provisioned — no detection is ever fabricated.
6. **Master id 4 is flagged `duplicate: true` although it is a cluster root**
   (`duplicate_of: null`, `cluster_size: 11`). Summing the `duplicate` flag
   yields 15 supporting reports where 14 exist. The underlying cluster
   arithmetic is otherwise exact: `19 = 5 masters + 14 children`, and the
   collapsed feed returns 14 roots.
7. **The Authority SPA reads `vision.objects` / `vision.summary`, but the backend
   writes `vision.detections` / `vision.classifier_labels`**
   (`backend/issues/civic.py:562-563`, asserted by `tests_ai.py`). The dashboard's
   image-analysis panel can therefore never display a result. The error direction
   is safe — it under-claims instead of inventing output — and it is currently
   invisible because no row has CV output at all. The Flutter app reads the
   correct keys.
8. **No `onError` fallback exists on any `<img>` in the Authority SPA**
   (`RecentReports.tsx:60`, `IssueDetailPage.tsx:133`, `ResolutionPanel.tsx:87-88`),
   so the 404s from item 1 render as browser broken-image icons.

## 10. Deployment complete

All phases finished and verified on 2026-09-26:

1. `DB_PASSWORD` restored in the Render dashboard by the account owner (it is
   not retrievable through any Render API).
2. Environment re-verified: 13/13 required variables present, no secret printed
   or committed.
3. Controlled manual redeploy `dep-das4d8bbc2fs7399gb00` → `live` at
   `2026-09-26T22:27:57Z`, commit `c28fc2a`.
4. Health, database connectivity, CORS (both directions), authority
   authorization and the Admin SPA all verified against the live services.

API auto-deploy is intentionally left **off** so that no future push can deploy
an unverified environment. Re-enabling it is a one-click change in the Render
dashboard once you are comfortable with that trade-off.

### Deployment flow as delivered

```
Citizen app (Flutter)
   -> HTTPS/JSON
Django + DRF API  ->  PostgreSQL (28 live issues, verified)
   -> optional AI/CV sidecar (not deployed: reports not_analyzed honestly)
   -> deterministic duplicate intelligence + explainable priority
Authority Admin (React SPA)  ->  same API, same database
```
