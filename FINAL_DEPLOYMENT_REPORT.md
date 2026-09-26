# FINAL DEPLOYMENT REPORT — FixMyGrid (Civic Intelligence)

**Status: production prototype DEPLOYED, with one pending API redeploy.**
Last updated: 2026-09-26 (UTC)

---

## 1. Live URLs

| What | URL | Verified |
| --- | --- | --- |
| GitHub repository | https://github.com/sujal27-KMSSV/civic-intelligencemobile | yes — `main` @ `29719b0` |
| Django API | https://civic-intelligence-api.onrender.com | yes — `/api/health/` → `200 {"status":"ok"}` |
| Authority Admin | https://civic-intelligence-authority.onrender.com | yes — `/`, `/login`, `/issues/123` all `200` HTML |

## 2. Deployment status

| Service | Render type | State | Commit |
| --- | --- | --- | --- |
| `civic-intelligence-api` | `web_service` (Docker, `backend/`, free) | **live** | `b2cb9fe` (pre-existing deploy) |
| `civic-intelligence-authority` | `static_site` (`authority-web/`, free) | **live** | `29719b0` |
| `civic-intelligence-ai` | not created | intentionally not provisioned — it is a **paid** service and the API does not need it | — |

The Admin static site was created and built successfully from this repository.
The API is live and serving, but is still running its previous deploy.

**Pending:** the API must be redeployed to activate the new CORS setting (see §4).
The API's auto-deploy was switched **off** on purpose so that no push can deploy
an incomplete configuration. Re-enable it after the redeploy is verified.

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

## 4. CORS

Configured value on the API service (scheme + host only, comma-separated, no
trailing slash, no path, no `:443`, no wildcard):

```text
CORS_ALLOW_ALL_ORIGINS=False
CORS_ALLOWED_ORIGINS=https://civic-intelligence-api.onrender.com,https://civic-intelligence-authority.onrender.com
CSRF_TRUSTED_ORIGINS=https://civic-intelligence-api.onrender.com,https://civic-intelligence-authority.onrender.com
```

- The pre-existing legitimate origin (the API's own host) was **preserved**.
- Django reads CORS at process start, so the API must be **redeployed** for this
  to take effect. Until then the preflight returns `200` with an empty
  `Access-Control-Allow-Origin`, and the Admin cannot call the API from a browser.
- The same values are pinned in `render.yaml` so a fresh deploy reproduces them.

## 5. Production verification performed

| Check | Result |
| --- | --- |
| `GET /api/health/` | PASS — `200 {"status":"ok"}` |
| Admin `/`, `/login`, `/issues/123`, `/map`, `/analytics`, nested routes | PASS — `200` HTML (SPA rewrite works) |
| Admin hashed JS/CSS assets (5 files) | PASS — `200`, correct content types |
| Missing asset `/assets/<nope>.js` | PASS — `404` (rewrite is not a file catch-all) |
| `OPTIONS /api/issues/` with the Admin origin | **PENDING** — needs the API redeploy |
| `OPTIONS /api/issues/` with `https://evil.example` | must return no `Access-Control-Allow-Origin` |
| Public `GET /api/issues/` | PASS — 28 rows, 32 fields incl. `priority_label`, `priority_reasons`, `priority_model_score`, `vision` |
| Anonymous `/api/authority/issues/`, `/stats/`, `/hotspots/` | PASS — `401` |
| Invalid token on `/api/authority/issues/` | PASS — `401` |
| `GET /api/authority/meta/` | `404` — Admin falls back safely |
| `GET /api/hotspots/` | PASS — 5 cells |
| Public feed does not leak internal assignment | PASS — `assigned_to` / `assigned_at` absent (resolution outcome is intentionally public) |

## 6. Test summary (this repository, measured)

| Suite | Command | Result |
| --- | --- | --- |
| Django | `python manage.py test` | **113 passed, 4 skipped** (PostGIS skips) |
| Migrations | `makemigrations --check --dry-run` | No changes detected |
| Flutter | `flutter test` | **171/171 passed** |
| Flutter static analysis | `flutter analyze` | 2 info-level `prefer_const_constructors` lints in a test file; no errors/warnings |
| AI sidecar | `python -m pytest tests -q` | **9/9 passed** (torch 2.14.0+cpu, torchvision 0.29.0+cpu) |

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
  per-factor reasons, not a learned model.
- The optional `ai_service` sidecar contains **real** torch code (ResNet18/
  MobileNet-style CNN embeddings, YOLOv8n COCO detection) and is unit-tested
  (9 tests), but it is **not deployed** on the free tier. When
  `AI_SERVICE_URL` is empty the API honestly reports
  `vision = {"status": "not_analyzed", "service": null}` and the UI says so.
- No claim is made that the software prevents the civic problems it addresses.

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

## 10. Next step to finish

1. Supply the managed-Postgres `DB_PASSWORD` for `civic-intelligence-api`
   (see the handover note — it is not retrievable through the Render API).
2. Redeploy the API; confirm `OPTIONS /api/issues/` with the Admin origin
   returns `Access-Control-Allow-Origin: https://civic-intelligence-authority.onrender.com`.
3. Confirm `https://evil.example` receives no `Access-Control-Allow-Origin`.
4. Re-enable auto-deploy on the API.
