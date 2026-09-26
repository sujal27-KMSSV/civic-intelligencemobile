# Security

Security posture that must remain intact on every release. These are enforced
server-side and covered by the Django test suite; the mobile app additionally
keeps secrets in `flutter_secure_storage`, never in plain files.

## 1. Authentication & authorization

- DRF token auth for citizens; staff checks (`is_staff`) on every authority
  endpoint (`permissions.IsAdminUser`).
- Ownership enforced per object: a non-staff user may only read/write their
  own reports (`IsOwnerOrStaff` in `issues/views.py`).

## 2. Account isolation

- My Reports is filtered by `reporter=request.user` — never by anything the
  client sends.
- Proven in E2E both directions (A never sees B, B never sees A).

## 3. Writer allow-lists (no client trust)

- On **create**, the civic-analysis fields (severity, priority, confidence,
  duplicate, duplicate_of, department, analysis, status, …) are owned by the
  backend; the client may only supply `image, image_source, description,
  latitude, longitude, address, category`. See `perform_create` in
  `issues/views.py` and `AUTHORITY_OWNED_FIELDS`.
- On **PATCH**, a citizen may only change `description`/`address`; anything
  else returns 403 listing the disallowed fields. Staff are lifecycle-validated
  (`lifecycle.py`).

## 4. User deletion safety

- Delete is hard-blocked outside a **10-minute window** server-side
  (`delete_window_expired`), and the API reports `can_delete` so clients never
  show a button that would fail.
- Deleting a report **never corrupts a cluster**: child-delete recomputes the
  root, root-delete re-roots the orphans (`civic.recompute_root_after_child_removal`,
  `reroot_cluster_after_root_removal`).

## 5. Idempotency

- `client_request_id` is write-only, unique per reporter: a lost-response retry
  returns the original report (200) instead of a duplicate — atomically, even
  under concurrent identical posts.

## 6. File handling

- Images validated before storage (`issues/validators.py::validate_issue_image`)
  — size, dimensions (≥ 320px), format allow-list; stored through Django's
  storage backend; stored media removed on delete.
- Image decoding is everywhere wrapped in try/except (corrupt/unsupported
  files degrade gracefully to `null` features).

## 7. Transport & config

- Prod requires `DEBUG=False` (guarded: `SECRET_KEY` mandatory), HTTPS
  redirect + HSTS, explicit `ALLOWED_HOSTS`/`CSRF_TRUSTED_ORIGINS`/
  `CORS_ALLOWED_ORIGINS`, Whitenoise static.
- `render.yaml` uses `generateValue: true` for `SECRET_KEY`; the repo
  deliberately contains **no** live credentials.

## 8. Secret policy (scan before every commit)

- Never commit real passwords, tokens or API keys. `.env*` are gitignored;
  `.env.example` is the only committed template.
- The E2E suites self-register throwaway accounts; there are **no shared demo
  credentials** in the repository. Removed: the legacy `Demo@1234`
  fixture used by the old two-account test. Test-only fixture passwords (e.g.
  `Strong!DuelA9z`) exist only inside `integration_test/`, are scoped to fresh
  throwaway accounts and are not real user credentials.
- Pre-commit secret scan: `rg -n 'Demo@1234|P@ssw0rd|[A-Za-z0-9_]{30,}=' integration_test backend lib` — zero matches expected. If a scan flags
  anything, redact it and re-scan before pushing.

## 9. Not implemented / not claimed

- No WebSocket/realtime channel (polling + refresh only).
- Media `resolution_image` upload is authority-only; the similarity value is a
  heuristic image comparison and never auto-resolves an issue.
- Rate limiting on auth is implemented in Django (429 after N rapid attempts);
  other endpoints rely on normal DRF validation.