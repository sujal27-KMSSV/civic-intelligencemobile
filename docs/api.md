# API Reference (v1.1.0)

Base URLs: local `http://127.0.0.1:8000` · production `https://civic-intelligence-api.onrender.com`

The mobile app reads the **flattened** `IssueSerializer` payload on every
endpoint. Auth: DRF token auth for citizens; Django session/token for staff.

## Public (no auth)

| Endpoint | Behavior |
| --- | --- |
| `GET /api/health/` | `{"status":"ok"}` — Render health check |
| `GET /api/issues/` | Collapsed public feed. Masters only by default; `?collapse=0` returns every report. Ordered `-priority, -created_at` |
| `GET /api/issues/{id}/` | Detail incl. cluster context; 404 if missing |
| `GET /api/hotspots/` | Grid-bucketed heat-map cells from real open issues. `?grid=` (0.0001–0.05), `?limit=` (1–25) |

## Citizen (token auth)

| Endpoint | Behavior |
| --- | --- |
| `POST /api/issues/` | Multipart `image` + `image_source`, `description`, `latitude`, `longitude`, `category`, optional `client_request_id`, `address`. Engine runs server-side: duplicate/severity/priority/department. Returns 201 (or 200 with the existing report when `client_request_id` repeats) |
| `GET /api/issues/my-reports/` | The caller's own reports, newest first, never collapsed |
| `PATCH /api/issues/{id}/` | Non-staff may only change `description`/`address` (anything else → 403). Staff may drive lifecycle transitions (validated) |
| `DELETE /api/issues/{id}/` | Own reports only; enforced 10-minute delete window (`can_delete` mirrors this). Cluster bookkeeping runs before the row is dropped |

Server flags the app trusts: `can_delete`, `can_edit`.

## Staff-only (`/api/authority/...`)

| Endpoint | Behavior |
| --- | --- |
| `GET /api/authority/issues/` | unresolved first, then `-priority`, then oldest; filters `?status= ?severity= ?department= ?include_resolved=1` |
| `GET /api/authority/issues/{id}/` | detail + full `cluster` array |
| `POST /api/authority/issues/{id}/transition/` | `{"new_status": "verified"}` (lifecycle-validated) |
| `POST /api/authority/issues/{id}/resolve/` | multipart `image` + `notes` → resolves with honest BEFORE/AFTER similarity in `image_similarity` |
| `GET /api/authority/stats/` | counts by status/severity/department, open/duplicates/reported_today |
| `GET /api/authority/hotspots/` | hotspot cells incl. resolved/rejected history |

## Key response fields (Issues)

```json
{
  "id": 3, "image_url": "...", "description": "...", "category": "other",
  "latitude": 28.6139, "longitude": 77.209, "address": "",
  "status": "reported", "severity": "low",
  "duplicate": true, "duplicate_count": 2, "duplicate_of": null,
  "confidence": 0.72, "priority": 19.0, "priority_label": "low",
  "priority_reasons": [{ "factor": "duplicate_reports", "points": 4.0, "note": "..." }],
  "master_id": 3, "is_master": true, "cluster_size": 2,
  "cluster_member_ids": [3, 5], "can_delete": false, "can_edit": true
}
```

## Error conventions

- `400` validation/lifecycle, `401` unauthenticated, `403` permission/allow-list/delete-window,
  `404` missing, `429` rate-limited, `500` unexpected.
- `PATCH` by a citizen with a disallowed field returns a 403 message that lists
  exactly which fields were disallowed (see `issues/views.py`).