# Testing

Everything is green on `main`; see the live numbers in
[docs/claim-sheet.md](docs/claim-sheet.md).

## Backend — Django (113 tests)

```powershell
cd backend
py -3.14 -m venv .venv
.\.venv\Scripts\python.exe manage.py test        # 113 OK (skipped=4 PostGIS)
.\.venv\Scripts\python.exe manage.py makemigrations --check --dry-run
# "No changes detected"
```

Covers: duplicate clustering + hard veto + engine-v3 embedding/renormalization,
cluster bookkeeping after delete (child removed, root removed), idempotent
submission (sequential + concurrent), account isolation, PATCH allow-list,
delete window, lifecycle transitions, resolution verification, hotspots,
priority/scoring units, auth (staff vs citizen), file validation, AI-client
graceful degradation, geospat helpers + genuine PostGIS integration (skips
when `POSTGRES_GIS_ENABLED` is off).

## AI service — FastAPI (9 tests)

```powershell
cd ai_service
.\.venv\Scripts\python.exe -m pytest -q         # 9 OK (real CPU inference)
```

Real model inference (embed/classify/analyze/priority) + 503/400 error paths.

## Flutter — unit/widget (171 tests)

```powershell
flutter analyze          # clean except 2 pre-existing infos
flutter test             # 171 passing
```

Notable suites: `test/appearance_test.dart` (dark/light/system persistence),
`test/issue_cluster_parsing_test.dart` (master/child/cluster payloads),
`report_result_screen_test.dart` (honest labels: "96% similar", priority card),
`issues_details_screen_test.dart`, `test/navigation_regression_test.dart`
(back buttons, deep-link recovery), feed/repository/api-client tests.

## Integration E2E (on-device, real production API)

Both suites are **fully self-contained**: every account is a fresh throwaway
registered at runtime, and each ends the run with zero reports in the shared
database (no demo credential anywhere in VCS).

```powershell
flutter test integration_test/two_account_e2e_test.dart -d ZD2224MKS4
flutter test integration_test/network_failure_e2e_test.dart -d ZD2224MKS4
```

- **two_account_e2e_test.dart** — A self-registers → "No reports yet" →
  camera report R1 → "1 report" → gallery report R2 → "2 reports" → edit
  newest → delete newest → "1 report" → delete last → "No reports yet" →
  logout; B self-registers → sees NOTHING of A (isolation) → creates/edits →
  logout; A back in (still empty, no B reports); B back in (edit survived) →
  delete → empty → logout. Proves isolation in *both* directions, edit/delete
  gating (`can_edit`/`can_delete`), counters and empty states, and edit
  persistence across sessions.
- **network_failure_e2e_test.dart** — feed frozen into a guaranteed-offline
  state: asserts `Could not load reports`, `Check your connection and try
  again.`, a `Retry` button, **no** spinner and **no** half-rendered cards;
  network recovers → Retry heals the feed; relaunch restores the session
  straight to a healthy feed.

## String contracts

The E2E suites depend on exact UI strings (e.g. `Sign In`, `Create Account`,
`Register`, `Community Reports`, `My Reports`, `No reports yet`,
`1 report`/`2 reports`, `Edit`, `Delete`, `Edit report`, `Delete this report?`,
`Report updated.`, `Report deleted.`, `Report <id> submitted`,
`View My Reports`, `Could not load reports`, `Retry`, `Submit Report`,
`Open Camera`, `From Gallery`, `Add Location`, `NavigationBar`,
`View your reports`, `View Issue`, `Back to Home`). If a string changes, update
`e2e_helpers.dart` and the tests **in the same commit**.