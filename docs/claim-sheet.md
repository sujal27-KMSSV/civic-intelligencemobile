# Claim sheet — every claim, with evidence

Honesty contract: if something is not implemented it is marked `BLOCKED` /
`MISSING`, never asserted. Numbers below are reproducible from this repo
(Django 89 / Flutter 160 / live prod verification).

## Product claims

| # | Claim | Status | Evidence |
| --- | --- | --- | --- |
| 1 | Citizens can report an issue with photo, location, category and description | IMPLEMENTED | `issues/views.py::perform_create`; E2E `two_account_e2e_test.dart` |
| 2 | Duplicate reports are consolidated into a master issue (cluster) | IMPLEMENTED | `civic.py::run_analysis`; `test/issue_cluster_parsing_test.dart`; live `/api/issues/` master cards |
| 3 | Duplicate consolidation is explainable (per-signal evidence) | IMPLEMENTED | `duplicate_similarity_score` → `analysis["duplicate"]["evidence"]`; UI "Consolidated under Issue #id" |
| 4 | Priority is rule-based and explainable (0–100 + reasons) | IMPLEMENTED | `civic.py::score_priority`; `PriorityChip`; `report_result_screen_test.dart` |
| 5 | Priority is *not* an ML model output | IMPLEMENTED (honest) | `engine_honest_label` in analysis; labels "Explainable priority" / "Similarity to existing reports" |
| 6 | Hotspots computed from real open-issue data | IMPLEMENTED | `cluster_hotspots`; live `/api/hotspots/` 200 with aggregates |
| 7 | Department routing is deterministic | IMPLEMENTED | `DEPARTMENT_BY_CATEGORY`; tests |
| 8 | Citizen My Reports is account-isolated | IMPLEMENTED | `MyReportsView`; E2E (both directions) |
| 9 | Edit/Delete gated by server flags (`can_edit`/`can_delete`) | IMPLEMENTED | serializer method fields; `window.py`; E2E |
| 10 | Submission is idempotent (`client_request_id`) | IMPLEMENTED | `views.py::create` incl. concurrent IntegrityError path; test suite |
| 11 | Resolution verification = honest image-similarity measurement (not auto-resolve) | IMPLEMENTED | `civic.py::image_similarity`; `authority/service.py::resolve_issue` |
| 12 | Dark mode / system appearance | IMPLEMENTED | `appearance_provider.dart`; `test/appearance_test.dart` |
| 13 | Two-account + network-failure E2E are self-contained (zero leftovers) | IMPLEMENTED | `integration_test/two_account_e2e_test.dart`, `network_failure_e2e_test.dart` |

## Engineering claims

| # | Claim | Status | Evidence |
| --- | --- | --- | --- |
| 14 | Backend test suite green | IMPLEMENTED | `python manage.py test` → **89 OK** (this session, re-run before final commit) |
| 15 | No pending migrations | IMPLEMENTED | `makemigrations --check --dry-run` → "No changes detected"; migration `0006` applied locally |
| 16 | Flutter analyze clean | IMPLEMENTED | 2 pre-existing `info` records in `test/api_client_test.dart:420,437` only |
| 17 | Flutter unit/widget suite green | IMPLEMENTED | `flutter test` → **160 passing** |
| 18 | Live prod endpoints verified post-deploy | VERIFIED (session) | `/api/health/`, `/api/issues/`, `/api/hotspots/` → 200 on Render |
| 19 | Signed APK + AAB for 1.1.0+5 built and verified | SEE BUILD SECTION | `release/` artifacts + apksigner output |
| 20 | On-device E2E green on `ZD2224MKS4` | SEE DEVICE SECTION | `flutter test integration_test/...` output |
| 21 | HEAD == origin/main after final push | SEE GIT SECTION | `git status` / `git log` |

## Non-claims (deliberately NOT asserted)

| Item | Status | Note |
| --- | --- | --- |
| PostGIS geo queries | BLOCKED | Render free Postgres lacks the extension; non-GIS grid + haversine used. Docs/`ai.md` say so |
| S3/R2 durable media | BLOCKED | no credentials; `MEDIA_STORAGE_BACKEND=s3` wired but unexercised (see `deployment.md`) |
| Trained CV / object detection | NOT IMPLEMENTED | rule-based dHash only; explicitly documented in `ai.md` |
| Embeddings / LLM / ONNX | NOT IMPLEMENTED | no such dependency ships; Python 3.14 + 512 MB Render constraints documented |
| Realtime push / WebSockets | NOT IMPLEMENTED | polling/refresh wording maintained |
| A roaming production demo account | REMOVED | legacy `finaldemo…` + `Demo@1234` removed from VCS and suites |

## Verification log (this session)

- Django tests: **89 OK** (`C:\dev\civic-intelligencemobile\backend`).
- `makemigrations --check --dry-run`: **No changes detected**; `showmigrations` → `0006 ... [X]`.
- Live local server smoke: `/api/health/` ok; `/api/issues/` collapsed masters with `master_id`/`cluster_size`/`cluster_member_ids`; `/api/hotspots/` ok.
- `flutter analyze`: only the 2 pre-existing infos. `flutter test`: **160 passing**.
- E2E suites rewritten self-contained (below); `rg` for `Demo@1234|finaldemo` → zero hits.
- README + `docs/` suite written; HARDENING_REPORT fixture paragraphs updated.