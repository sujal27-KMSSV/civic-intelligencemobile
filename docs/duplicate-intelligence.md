# Duplicate Intelligence (engine v2)

The engine combines four independent, explainable signals into one weighted
similarity score, then attaches a new report to an existing **cluster**
(master issue + supporting reports).

## Score

Implemented in `backend/issues/civic.py::duplicate_similarity_score`.

```text
score = gps_sim * 0.30
      + category_match * 0.15
      + text_sim * 0.25
      + image_sim * 0.30
```

| Signal | Computation |
| --- | --- |
| `gps` (0.30) | `1 - haversine_km(lat1,lon1,lat2,lon2)*1000 / 120.0` |
| `category` (0.15) | `1.0` if equal else `0.0` |
| `text` (0.25) | Jaccard over word tokens of the free-text descriptions |
| `image` (0.30) | `1 - Hamming(dHash64) / 64` when both photos decodable |

**Hard veto:** if the two locations are more than `DUPLICATE_RADIUS_M = 120 m`
apart the score is 0 regardless of text/photo — a location is required for
consolidation.

**Threshold:** `DUPLICATE_MIN_SCORE = 0.60`. Candidates are found by a
bounding-box pre-filter (`±0.002°`), then scanned newest-candidate order; the
best scoring candidate wins. Per-signal evidence for every match is stored in
`analysis["duplicate"]["evidence"]` so a merge is always explainable.

## Cluster model

- The cluster **root** (master) is the oldest report that first represented
  the underlying issue. New similar reports point `duplicate_of` at it.
- `duplicate_count` on the master = number of supporting reports (children)
  plus itself.
- `apply_priority` gives the master a +5 "consolidated master" uplift and the
  duplicate-reports factors, so "17 citizens report the same pothole" becomes
  one prioritized issue, not 17 tickets.
- The API surfaces: `master_id`, `is_master`, `cluster_size`,
  `cluster_member_ids` (only on the master), and on each report whether it was
  "Consolidated under Issue #masterId".

## Concurrency

Cluster joins are serialized: inside `run_analysis` the root row is locked with
`select_for_update()` inside `transaction.atomic()` (see the comments in
`civic.py::run_analysis`), so two simultaneous submissions cannot both read a
stale member count and double-count. Deletion bookkeeping is equally strict:

- deleting a **child** → `recompute_root_after_child_removal` fixes the
  surviving root's count/severity/priority and its `analysis` duplicate block;
- deleting a **root** → `reroot_cluster_after_root_removal` re-homes each
  orphan (oldest becomes the new root), keeping one root and consistent
  counts.

## When a second report is NOT created across the wire

If a mobile client re-posts with the same `client_request_id`, the server
returns the already-created report (HTTP 200) instead of minting a duplicate
row — even under concurrent identical requests (IntegrityError fallback). See
`issues/views.py::create`.

## Policy notes

- The public feed collapses clusters by default (`collapse=1` shows only
  masters); `?collapse=0` returns every report. My Reports never collapses.
- Reported fields are still called `confidence` in the JSON/DB schema for
  backward compatibility; the app renders them as "Similarity to existing
  reports" and the "analysis" block carries the per-signal evidence.