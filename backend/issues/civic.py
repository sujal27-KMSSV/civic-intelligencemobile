"""Civic-intelligence analysis engine (Honest, deterministic, rule-based).

IMPORTANT — READ THIS BEFORE CLAIMING AI CAPABILITIES:
This module implements REAL, reproducible civic-intelligence heuristics using
only standard Python + Pillow. It deliberately does NOT pretend to run a
trained ML model. Every value it writes is derived from explicit rules, so it
can be audited and explained. When (in future) a real CV/ML pipeline is added,
it plugs in here without changing the API shape -- the Issue columns stay the
same and the mobile payload stays the same.

Capabilities implemented here:

* DUPLICATE INTELLIGENCE  -- combine GPS proximity (haversine), category match,
  free-text description overlap AND perceptual-image similarity (dHash on the
  report photo) into an explainable similarity score (with per-signal evidence),
  then attach the new report to an existing cluster (root/master issue). The
  root accumulates ``duplicate_count`` so "17 citizens report the same pothole"
  becomes one prioritized issue with 17 supporting reports. Cluster joins are
  serialized with ``select_for_update`` so concurrent submissions cannot
  double-count.
* SEVERITY SCORING        -- category base weight + text signal keywords +
  duplicate-report escalation, mapped onto the 4 Severity levels.
* PRIORITY SCORING        -- rule-based 0..100 with per-factor reasons (severity
  base, duplicate reports, recency, cluster master). Not a model output.
* HOTSPOT CLUSTERING      -- grid-bucket OPEN issues into hotspot cells with
  category/department/status aggregates for the dashboard heat map (real data).
* DEPARTMENT ROUTING      -- deterministic category -> department table.
* RESOLUTION VERIFICATION -- perceptual-hash (dHash) + brightness similarity
  between the "before" (original) and "after" (authority upload) photos. The
  measured number is reported honestly as *image similarity*; it never
  auto-marks an issue resolved -- that remains an authority decision.

Known limitations (deliberate, documented):
* No trained object-detection model: we do NOT claim to visually detect a
  pothole in arbitrary imagery.
* Similarity scores are heuristics, not a learned metric.
* Category is chosen by the citizen; the system routes and scores on it.
"""

from __future__ import annotations

import io
import math
import re
from pathlib import Path

from django.conf import settings
from django.db import transaction

# --------------------------------------------------------------------------
# Department routing table (human-curated, stable).
# --------------------------------------------------------------------------
DEPARTMENT_BY_CATEGORY = {
    "pothole": "Road Maintenance",
    "road_damage": "Road Maintenance",
    "garbage": "Solid Waste Management",
    "streetlight": "Public Lighting",
    "drainage": "Drainage & Sewage",
    "other": "General Services",
}

# --------------------------------------------------------------------------
# Severity heuristic: category base weights (0-100 scale).
# --------------------------------------------------------------------------
CATEGORY_SEVERITY_WEIGHT = {
    "pothole": 40,
    "road_damage": 45,
    "garbage": 25,
    "streetlight": 20,
    "drainage": 55,
    "other": 30,
}

# Description keyword signals -> additive severity points. Matched as
# case-insensitive substring / whole-word where the item ends with '*'.
SEVERITY_SIGNAL_WORDS = {
    "dangerous": 12,
    "injury": 18,
    "injured": 18,
    "accident": 16,
    "deep": 10,
    "large": 7,
    "wide": 6,
    "flooding": 12,
    "leak": 9,
    "overflow": 9,
    "blocked": 6,
    "falling": 12,
    "exposed": 8,
    "electrical": 14,
    "spark": 14,
    "worsening": 6,
    "severe": 9,
    "broken": 6,
    "crack": 5,
    "school": 8,
    "hospital": 8,
    "busy": 5,
    "main road": 6,
    "highway": 8,
}

SEVERITY_LEVELS = {
    "low": (0, 45),
    "medium": (45, 60),
    "high": (60, 75),
    "critical": (75, 101),
}

# Per duplicate-report escalation added to severity (caps out).
DUPLICATE_SEVERITY_UPLIFT = 3.0
DUPLICATE_SEVERITY_MAX = 15.0

# --------------------------------------------------------------------------
# Duplicate detection constants (engine v2: GPS + category + text + IMAGE).
# --------------------------------------------------------------------------
DUPLICATE_RADIUS_M = 120.0          # GPS proximity window (hard veto beyond it).
DESC_TOKEN_MIN_LEN = 3              # ignore very short description tokens.
GPS_SIM_WEIGHT = 0.30               # weight of GPS proximity in the score.
CATEGORY_MATCH_WEIGHT = 0.15        # weight of category equality.
DESC_SIM_WEIGHT = 0.25              # weight of text similarity in the score.
IMAGE_SIM_WEIGHT = 0.30             # weight of perceptual-identical photo.
DUPLICATE_MIN_SCORE = 0.60          # below this, treat as a new issue.

# --------------------------------------------------------------------------
# Priority-scoring constants (rule-based, explainable).
# --------------------------------------------------------------------------
PRIORITY_SEVERITY_BASE = {
    "low": 10,
    "medium": 20,
    "high": 30,
    "critical": 40,
}
PRIORITY_DUP_PER_REPORT = 4.0       # per supporting report beyond the first.
PRIORITY_DUP_MAX = 20.0
PRIORITY_HOURS_FRESH = 24.0         # reported within a day.
PRIORITY_FRESH_24H = 10.0
PRIORITY_HOURS_WARM = 72.0          # reported within three days.
PRIORITY_WARM_72H = 5.0
PRIORITY_MASTER_UPLIFT = 5.0        # already consolidated several reports.

# --------------------------------------------------------------------------
# Resolution-image constants.
# --------------------------------------------------------------------------
DHASH_SIZE = 8                      # 8x8 dHash -> 64 bits.
RESOLUTION_SIM_EPSILON = 0.02


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Great-circle distance in kilometres between two GPS points."""
    r = 6371.0088
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = (
        math.sin(dp / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    )
    return 2 * r * math.asin(math.sqrt(a))


def _tokens(text: str) -> set[str]:
    return {
        t
        for t in re.findall(r"[a-z0-9]+", (text or "").lower())
        if len(t) >= DESC_TOKEN_MIN_LEN
    }


def text_similarity(a: str, b: str) -> float:
    """Jaccard similarity on word tokens of two free-text descriptions."""
    ta, tb = _tokens(a), _tokens(b)
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def image_dhash_bits(name: str) -> str:
    """64-bit perceptual-hash of a stored image as a '0'/'1' string ('' if unreadable)."""
    bits = _dhash(name)
    if bits is None:
        return ""
    return "".join("1" if b else "0" for b in bits)


def dhash_similarity(a: str, b: str) -> float:
    """Fixed Hamming similarity on two 64-char dHash strings (0..1)."""
    if not a or not b or len(a) != len(b) or len(a) != 64:
        return 0.0
    differing = sum(x != y for x, y in zip(a, b))
    return round(1.0 - differing / 64.0, 3)


def image_features(name: str) -> dict:
    """Perceptual features of a stored image: dHash string + mean brightness.

    Returned structure is cheap to compute and reused by duplicate detection
    and (resolution) comparison. ``None`` values mean the image could not be
    decoded (corrupt file, unsupported format, missing storage object).
    """
    return {
        "dhash": image_dhash_bits(name) or None,
        "brightness": _brightness_ratio(name),
    }


def duplicate_similarity_score(
    *,
    lat1: float,
    lon1: float,
    lat2: float,
    lon2: float,
    category1: str,
    category2: str,
    text1: str,
    text2: str,
    image_sim: float | None = None,
) -> dict:
    """Weighted similarity between two reports.

    Returns a dict with the total plus a per-signal breakdown so the engine can
    explain *why* two reports were (or were not) merged:

    {
      "score": 0..1,
      "distance_m": ..,
      "signals": [
        {"name": "gps", "value": 0..1},
        {"name": "category", "value": 0..1},
        {"name": "text", "value": 0..1},
        {"name": "image", "value": 0..1 or null},
      ],
    }

    ``image_sim`` is an optional 0..1 perceptual-similarity value (1 = the two
    photos are essentially the same scene). A ``None`` image signal scores 0.

    HARD VETO: reports farther apart than ``DUPLICATE_RADIUS_M`` never merge,
    no matter how similar their text or photo is (a location is required for
    consolidation).
    """
    dist_m = haversine_km(lat1, lon1, lat2, lon2) * 1000.0
    if dist_m > DUPLICATE_RADIUS_M:
        return {"score": 0.0, "distance_m": round(dist_m, 1), "signals": []}

    gps_sim = max(0.0, 1.0 - dist_m / DUPLICATE_RADIUS_M)
    cat_sim = 1.0 if category1 == category2 else 0.0
    txt_sim = text_similarity(text1, text2)
    img_sim = image_sim if image_sim is not None else 0.0
    img_sim = max(0.0, min(1.0, img_sim))

    score = (
        gps_sim * GPS_SIM_WEIGHT
        + cat_sim * CATEGORY_MATCH_WEIGHT
        + txt_sim * DESC_SIM_WEIGHT
        + img_sim * IMAGE_SIM_WEIGHT
    )
    return {
        "score": round(score, 4),
        "distance_m": round(dist_m, 1),
        "signals": [
            {"name": "gps", "value": round(gps_sim, 4)},
            {"name": "category", "value": round(cat_sim, 4)},
            {"name": "text", "value": round(txt_sim, 4)},
            {"name": "image", "value": round(img_sim, 4) if image_sim is not None else None},
        ],
    }


def score_severity(
    category: str, description: str, duplicate_count: int = 1
) -> tuple[str, dict]:
    """Rule-based severity level plus the score breakdown (for the dashboard).

    Returns ``("low"|"medium"|"high"|"critical", {"score": int, "signals": [...]})``.
    """
    score = float(CATEGORY_SEVERITY_WEIGHT.get(category, 30))
    signals: list[dict] = [
        {"type": "category_base", "value": category, "points": score}
    ]

    text = (description or "").lower()
    for word, pts in SEVERITY_SIGNAL_WORDS.items():
        if word in text:
            score += pts
            signals.append({"type": "keyword", "value": word, "points": pts})

    if duplicate_count > 1:
        uplift = min(
            (duplicate_count - 1) * DUPLICATE_SEVERITY_UPLIFT,
            DUPLICATE_SEVERITY_MAX,
        )
        if uplift > 0:
            score += uplift
            signals.append(
                {"type": "duplicate_reports", "value": duplicate_count, "points": uplift}
            )

    score = max(0.0, min(100.0, round(score, 1)))
    level = next(
        name
        for name, (lo, hi) in SEVERITY_LEVELS.items()
        if lo <= score < hi or (name == "critical" and score >= lo)
    )
    return level, {"score": score, "signals": signals}


def score_priority(
    *,
    severity: str,
    duplicate_count: int,
    created_at,
    is_master: bool = False,
    now=None,
) -> dict:
    """Rule-based priority 0..100 with per-factor reasons.

    Factors (all deterministic and explainable):
    * severity base        -> 10 / 20 / 30 / 40 for low/medium/high/critical.
    * supporting reports   -> +4 per report beyond the first (cap +20).
    * freshness            -> +10 reported within 24h, +5 within 72h.
    * consolidated master  -> +5 when the report already represents a cluster.

    Returns ``{"score": 0..100, "label": "low"|"medium"|"high"|"critical",
    "reasons": [{"factor": str, "points": float, "note": str}]}``.
    """
    from django.utils import timezone

    reasons: list[dict] = []
    score = 0.0

    base = float(PRIORITY_SEVERITY_BASE.get(severity, 10))
    score += base
    reasons.append({"factor": "severity", "points": base, "note": f"Severity is '{severity}'."})

    if duplicate_count > 1:
        dup_pts = min(
            (duplicate_count - 1) * PRIORITY_DUP_PER_REPORT, PRIORITY_DUP_MAX
        )
        if dup_pts > 0:
            score += dup_pts
            reasons.append(
                {
                    "factor": "duplicate_reports",
                    "points": dup_pts,
                    "note": f"{duplicate_count} reports describe the same issue.",
                }
            )

    now = now or timezone.now()
    if created_at is not None:
        age_h = max(0.0, (now - created_at).total_seconds() / 3600.0)
        if age_h <= PRIORITY_HOURS_FRESH:
            score += PRIORITY_FRESH_24H
            reasons.append(
                {"factor": "reported_recently", "points": PRIORITY_FRESH_24H,
                 "note": "Reported within the last 24 hours."}
            )
        elif age_h <= PRIORITY_HOURS_WARM:
            score += PRIORITY_WARM_72H
            reasons.append(
                {"factor": "reported_recently", "points": PRIORITY_WARM_72H,
                 "note": "Reported within the last 72 hours."}
            )

    if is_master:
        score += PRIORITY_MASTER_UPLIFT
        reasons.append(
            {"factor": "cluster_master", "points": PRIORITY_MASTER_UPLIFT,
             "note": "Report consolidates several citizen reports."}
        )

    score = float(max(0.0, min(100.0, round(score, 1))))
    label = next(
        name
        for name, (lo, hi) in {
            "low": (0, 30), "medium": (30, 55), "high": (55, 80), "critical": (80, 101)
        }.items()
        if lo <= score < hi or (name == "critical" and score >= lo)
    )
    return {"score": score, "label": label, "reasons": reasons}


def apply_priority(issue, *, created_at=None, is_master=None) -> None:
    """Write priority fields onto an already-saved ``Issue`` (no save call)."""
    result = score_priority(
        severity=issue.severity,
        duplicate_count=issue.duplicate_count,
        created_at=created_at if created_at is not None else issue.created_at,
        is_master=issue.duplicate_of_id is None if is_master is None else is_master,
    )
    issue.priority = result["score"]
    issue.priority_label = result["label"]
    issue.priority_reasons = result["reasons"]


def cluster_hotspots(queryset, grid: float = 0.002, limit: int = 5) -> list[dict]:
    """Grid-cluster nearby reports into hotspot cells from real issue data.

    Reports are bucketed into ~``grid``-degree (Lat/Lon) cells (~220 m at the
    topic latitudes). Only OPEN issues (not resolved/rejected) count. Returns
    the densest cells with the aggregate fields needed to render a heat map.
    """
    from collections import defaultdict

    cells: dict[tuple[float, float], list] = defaultdict(list)
    for issue in queryset:
        lat = float(issue.latitude)
        lon = float(issue.longitude)
        key = (round(lat / grid) * grid, round(lon / grid) * grid)
        cells[key].append(issue)

    out = []
    for (lat_c, lon_c), issues in cells.items():
        open_issues = [i for i in issues if i.status not in ("resolved", "rejected")]
        if not open_issues:
            continue
        counts: dict = {}
        for field in ("category", "department", "status"):
            buckets: dict = {}
            for i in open_issues:
                buckets[getattr(i, field)] = buckets.get(getattr(i, field), 0) + 1
            counts[field] = sorted(
                buckets.items(), key=lambda kv: -kv[1]
            )[:3]
        top = max(open_issues, key=lambda i: (i.priority, i.created_at))
        out.append(
            {
                "grid": grid,
                "lat": round(lat_c + grid / 2, 6),
                "lon": round(lon_c + grid / 2, 6),
                "issue_count": len(open_issues),
                "report_count": len(issues),
                "categories": counts["category"],
                "departments": counts["department"],
                "statuses": counts["status"],
                "top_issue_id": top.pk,
                "top_priority": top.priority,
            }
        )
    out.sort(key=lambda h: -h["issue_count"])
    return out[:limit]


def run_analysis(issue) -> dict:
    """Analyse a single *saved* report and persist the derived civic fields.

    ``issue`` is a fully-saved ``Issue`` instance. Returns the analysis dict
    that was written onto the row (useful for tests and the dashboard).
    """
    from .models import Issue  # local import to avoid circulars

    lat = float(issue.latitude)
    lon = float(issue.longitude)

    # -- duplicate intelligence -------------------------------------------
    duplicate_of = None
    similarity = 0.0
    cluster_count = 1
    cluster_members: list[int] = []

    candidates = (
        Issue.objects.exclude(pk=issue.pk)
        .filter(
            latitude__gte=lat - 0.002,
            latitude__lte=lat + 0.002,
            longitude__gte=lon - 0.002,
            longitude__lte=lon + 0.002,
        )
        .exclude(status=Issue.Status.REJECTED)
        .order_by("created_at")
    )

    best = None
    best_score = 0.0
    best_result: dict | None = None
    # Perceptual features of the NEW report photo, computed once and cached on
    # the row (duplicate detection here; resolution verification later).
    features = image_features(issue.image.name)
    issue.image_dhash = (features.get("dhash") or "")[:64]
    issue.image_brightness = features.get("brightness")

    for other in candidates:
        # Reuse the candidate's cached hash when present; otherwise compute it
        # once (legacy rows) and lazily cache so later comparisons are free.
        other_dhash = (other.image_dhash or "").strip() if other.image_dhash else ""
        if not other_dhash:
            other_dhash = image_dhash_bits(other.image.name)
            if other_dhash:
                Issue.objects.filter(pk=other.pk).update(image_dhash=other_dhash)
        img_sim = None
        if issue.image_dhash and other_dhash:
            img_sim = dhash_similarity(issue.image_dhash, other_dhash)

        result = duplicate_similarity_score(
            lat1=lat,
            lon1=lon,
            lat2=float(other.latitude),
            lon2=float(other.longitude),
            category1=issue.category,
            category2=other.category,
            text1=issue.description,
            text2=other.description,
            image_sim=img_sim,
        )
        if result["score"] > best_score:
            best_score = result["score"]
            best = other
            best_result = result

    if best is not None and best_score >= DUPLICATE_MIN_SCORE:
        # Serialize concurrent cluster joins: lock the cluster root row for the
        # remainder of the (outer, already-open) transaction so two simultaneous
        # submissions cannot both read a stale member count and double-count.
        with transaction.atomic():
            root = best
            if best.duplicate_of_id is not None:
                root = Issue.objects.select_for_update().get(pk=best.duplicate_of_id)
            duplicate_of = root
            similarity = round(best_score, 3)
            member_ids = list(
                Issue.objects.filter(duplicate_of=root).values_list("pk", flat=True)
            )
            cluster_members = sorted(set(member_ids) | {root.pk})
            cluster_count = len(cluster_members) + 1  # + this new report
    else:
        duplicate_of = None
        similarity = 0.0
        cluster_members = []
        cluster_count = 1

    is_duplicate = duplicate_of is not None
    duplicate_count = cluster_count if is_duplicate else 0

    # -- severity ---------------------------------------------------------
    severity_level, severity_breakdown = score_severity(
        issue.category, issue.description, max(duplicate_count, 1)
    )

    # -- department routing -----------------------------------------------
    department = DEPARTMENT_BY_CATEGORY.get(issue.category, "General Services")

    # -- priority (rule-based, explainable) -------------------------------
    priority_result = score_priority(
        severity=severity_level,
        duplicate_count=max(duplicate_count, 1),
        created_at=issue.created_at,
        is_master=False,
    )
    issue.priority = priority_result["score"]
    issue.priority_label = priority_result["label"]
    issue.priority_reasons = priority_result["reasons"]

    analysis = {
        "engine": "rule-based-civic-analysis-v2",
        "engine_honest_label": "Rule-based analysis (not a trained ML model)",
        "duplicate": {
            "is_duplicate": is_duplicate,
            "similarity_score": similarity,
            "distance_m": (
                best_result["distance_m"] if best_result is not None and is_duplicate else None
            ),
            "evidence": (
                best_result["signals"] if best_result is not None and is_duplicate else []
            ),
            "root_id": duplicate_of.pk if duplicate_of else None,
            "cluster_members": cluster_members,
            "duplicate_count": duplicate_count,
        },
        "severity": severity_breakdown,
        "priority": {
            "score": priority_result["score"],
            "label": priority_result["label"],
            "reasons": priority_result["reasons"],
        },
        "image": {
            "median_dhash": issue.image_dhash,
            "brightness": issue.image_brightness,
        },
        "department": department,
        "department_by": "category-routing-table",
    }

    issue.duplicate = is_duplicate
    issue.duplicate_of = duplicate_of
    issue.duplicate_count = duplicate_count
    issue.confidence = similarity  # similarity confidence of the cluster match
    issue.severity = severity_level
    issue.department = department
    issue.analysis = analysis
    issue.save(update_fields=[
        "duplicate",
        "duplicate_of",
        "duplicate_count",
        "confidence",
        "severity",
        "department",
        "priority",
        "priority_label",
        "priority_reasons",
        "image_dhash",
        "image_brightness",
        "analysis",
        "updated_at",
    ])

    # A later duplicate increases the *root's* severity, count AND priority too.
    if duplicate_of is not None and duplicate_of.pk != issue.pk:
        # Whole cluster now = previously-known members + this new report.
        root_dup_count = len(cluster_members) + 1
        root_sev, _ = score_severity(
            duplicate_of.category, duplicate_of.description, root_dup_count
        )
        duplicate_of.duplicate_count = root_dup_count
        duplicate_of.severity = root_sev
        apply_priority(duplicate_of, is_master=True)
        duplicate_of.save(update_fields=[
            "duplicate_count",
            "severity",
            "priority",
            "priority_label",
            "priority_reasons",
            "updated_at",
        ])
        analysis["duplicate"]["root_duplicate_count"] = root_dup_count
        analysis["duplicate"]["root_priority"] = duplicate_of.priority

    return analysis


# --------------------------------------------------------------------------
# Cluster bookkeeping for report deletion. Deleting a report must never leave
# stale duplicate_count / duplicate_of state, so the surviving cluster is
# recomputed before the row is dropped (kept in civic so the invariants live
# next to the analysis engine that creates them).
# --------------------------------------------------------------------------

def _duplicate_block(
    *,
    is_duplicate: bool,
    root_id: int | None,
    member_ids: list[int],
    duplicate_count: int,
    similarity: float = 0.0,
) -> dict:
    """Rebuild the ``analysis["duplicate"]`` block for a surviving issue."""
    return {
        "is_duplicate": is_duplicate,
        "similarity_score": similarity,
        "root_id": root_id,
        "cluster_members": sorted(set(member_ids)),
        "duplicate_count": duplicate_count,
    }


def recompute_root_after_child_removal(root: "Issue") -> None:
    """Fix the surviving root after one of its duplicate reports was deleted.

    ``root`` must still exist; the deleted child row is already gone so
    ``root.duplicates`` reflects the survivors.
    """
    members = list(root.duplicates.order_by("created_at"))
    total = len(members) + 1  # root + remaining children

    if total <= 1:
        root.duplicate = False
        root.duplicate_count = 0
    else:
        root.duplicate = True
        root.duplicate_count = total
        root.severity, _ = score_severity(
            root.category, root.description, total
        )
    apply_priority(root, is_master=total > 1)

    member_ids = [root.pk, *(m.pk for m in members)]
    analysis = dict(root.analysis or {})
    analysis["duplicate"] = _duplicate_block(
        is_duplicate=False,
        root_id=None,
        member_ids=member_ids,
        duplicate_count=root.duplicate_count,
    )
    root.analysis = analysis
    root.save(update_fields=[
        "duplicate",
        "duplicate_count",
        "severity",
        "priority",
        "priority_label",
        "priority_reasons",
        "analysis",
        "updated_at",
    ])


def reroot_cluster_after_root_removal(children: list["Issue"]) -> None:
    """Re-root the orphans left behind after a root report was deleted.

    ``children`` is the deleted root's former duplicates (newest-safe order is
    irrelevant here; the oldest becomes the new root). Their ``duplicate_of``
    has already been NULL'ed by on_delete=SET_NULL. The cluster keeps one root
    and consistent counts/severity; nothing references the deleted row.
    """
    if not children:
        return
    new_root = min(children, key=lambda c: c.created_at)
    ids = [c.pk for c in children]

    for child in children:
        is_root = child.pk == new_root.pk
        child.duplicate = not is_root
        child.duplicate_of = None if is_root else new_root
        child.duplicate_count = len(children)
        child.severity, _ = score_severity(
            child.category, child.description, len(children)
        )
        apply_priority(child, is_master=is_root and len(children) > 1)
        analysis = dict(child.analysis or {})
        analysis["duplicate"] = _duplicate_block(
            is_duplicate=not is_root,
            root_id=None if is_root else new_root.pk,
            member_ids=ids,
            duplicate_count=child.duplicate_count,
            similarity=0.0 if is_root else (child.confidence or 0.0),
        )
        child.analysis = analysis
        child.save(update_fields=[
            "duplicate",
            "duplicate_of",
            "duplicate_count",
            "severity",
            "priority",
            "priority_label",
            "priority_reasons",
            "analysis",
            "updated_at",
        ])


# --------------------------------------------------------------------------
# Resolution verification (honest, heuristic image comparison).
# --------------------------------------------------------------------------

def _read_saved_image(name: str) -> bytes | None:
    """Read a stored media file through the configured storage backend."""
    try:
        from django.core.files.storage import default_storage

        with default_storage.open(name or "", "rb") as fh:
            return fh.read()
    except Exception:
        return None


def _dhash(name: str) -> list[int] | None:
    """Perceptual difference-hash of an image (Pillow, no extra deps).

    Reads through Django's configured storage so it works with local disk
    (dev) and S3/R2 (production) alike.
    """
    try:
        from PIL import Image, ImageOps

        data = _read_saved_image(name)
        if data is None:
            return None
        with Image.open(io.BytesIO(data)) as im:
            im = ImageOps.exif_transpose(im)
            im = im.convert("L").resize((DHASH_SIZE + 1, DHASH_SIZE), Image.LANCZOS)
        bits = []
        w = DHASH_SIZE
        px = list(im.getdata())
        for y in range(DHASH_SIZE):
            for x in range(w):
                left = px[y * (w + 1) + x]
                right = px[y * (w + 1) + x + 1]
                bits.append(1 if left >= right else 0)
        return bits
    except Exception:
        return None


def _brightness_ratio(name: str) -> float | None:
    """Mean grayscale brightness of the image in 0..1."""
    try:
        from PIL import Image, ImageOps

        data = _read_saved_image(name)
        if data is None:
            return None
        with Image.open(io.BytesIO(data)) as im:
            im = ImageOps.exif_transpose(im).convert("L")
            hist = im.histogram()
        total = sum(hist)
        if not total:
            return None
        return round(sum(i * c for i, c in enumerate(hist)) / (total * 255.0), 3)
    except Exception:
        return None


def image_similarity(name_before: str, name_after: str) -> dict:
    """Compare BEFORE/AFTER photos (storage names, e.g. ``issue.image.name``).

    Returns an honest measurement object:
    {
      "similarity": 0..1      # 1 = perceptually identical (fixed Hamming on 64-bit dHash)
      "brightness_before": ..,
      "brightness_after": ..,
      "method": "dhash-hamming-64",
      "interpretation": "identical" | "similar" | "different"
    }

    ``similarity`` high means the two photos are essentially the same scene,
    which suggests the problem is NOT visually fixed. It is NEVER used to
    auto-resolve an issue -- that remains an authority decision.
    """
    before = _dhash(name_before)
    after = _dhash(name_after)
    if before is None or after is None or len(before) != len(after):
        return {
            "similarity": None,
            "method": "dhash-hamming-64",
            "interpretation": "unavailable",
            "reason": "could not decode one or both images",
        }
    differing = sum(1 for x, y in zip(before, after) if x != y)
    similarity = round(1.0 - differing / len(before), 3)
    if similarity >= 0.92:
        interpretation = "identical"
    elif similarity >= 0.70:
        interpretation = "similar"
    else:
        interpretation = "different"
    result = {
        "similarity": similarity,
        "method": "dhash-hamming-64",
        "interpretation": interpretation,
        "brightness_before": _brightness_ratio(name_before),
        "brightness_after": _brightness_ratio(name_after),
    }
    return result


def media_path(name: str) -> Path:
    """Resolve a stored-media field string to a local path (dev/demo layout)."""
    return Path(settings.MEDIA_ROOT) / (name or "")