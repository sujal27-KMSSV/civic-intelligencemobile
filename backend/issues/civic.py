"""Civic-intelligence analysis engine (Honest, deterministic, rule-based).

IMPORTANT — READ THIS BEFORE CLAIMING AI CAPABILITIES:
This module implements REAL, reproducible civic-intelligence heuristics using
only standard Python + Pillow. It deliberately does NOT pretend to run a
trained ML model. Every value it writes is derived from explicit rules, so it
can be audited and explained. When (in future) a real CV/ML pipeline is added,
it plugs in here without changing the API shape -- the Issue columns stay the
same and the mobile payload stays the same.

Capabilities implemented here:

* DUPLICATE INTELLIGENCE  -- combine GPS proximity (haversine), category match
  and free-text description overlap into a similarity score, then attach the
  new report to an existing cluster (root issue). The root accumulates
  ``duplicate_count`` so "17 citizens report the same pothole" becomes one
  prioritized issue with 17 reports.
* SEVERITY SCORING        -- category base weight + text signal keywords +
  duplicate-report escalation, mapped onto the 4 Severity levels.
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
# Duplicate detection constants.
# --------------------------------------------------------------------------
DUPLICATE_RADIUS_M = 120.0          # GPS proximity window.
DESC_TOKEN_MIN_LEN = 3              # ignore very short description tokens.
DESC_SIM_WEIGHT = 0.4               # weight of text similarity in the score.
GPS_SIM_WEIGHT = 0.4                # weight of GPS proximity in the score.
CATEGORY_MATCH_WEIGHT = 0.2         # weight of category equality.
DUPLICATE_MIN_SCORE = 0.60          # below this, treat as a new issue.

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
) -> float:
    """Weighted similarity between two reports (0..1, higher = more alike).

    Components (deterministic, explainable):
    * GPS proximity  -> linear 1.0 at 0 m down to 0.0 at DUPLICATE_RADIUS_M.
    * category match -> 1.0 when equal else 0.0.
    * text overlap   -> Jaccard token overlap on descriptions.
    """
    dist_m = haversine_km(lat1, lon1, lat2, lon2) * 1000.0
    gps_sim = max(0.0, 1.0 - dist_m / DUPLICATE_RADIUS_M)
    cat_sim = 1.0 if category1 == category2 else 0.0
    txt_sim = text_similarity(text1, text2)
    return (
        gps_sim * GPS_SIM_WEIGHT
        + cat_sim * CATEGORY_MATCH_WEIGHT
        + txt_sim * DESC_SIM_WEIGHT
    )


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
    for other in candidates:
        score = duplicate_similarity_score(
            lat1=lat,
            lon1=lon,
            lat2=float(other.latitude),
            lon2=float(other.longitude),
            category1=issue.category,
            category2=other.category,
            text1=issue.description,
            text2=other.description,
        )
        if score > best_score:
            best_score = score
            best = other

    if best is not None and best_score >= DUPLICATE_MIN_SCORE:
        root = best.duplicate_of if best.duplicate_of_id is not None else best
        duplicate_of = root
        similarity = round(best_score, 3)
        member_ids = list(
            Issue.objects.filter(duplicate_of=root).values_list("pk", flat=True)
        )
        cluster_members = sorted(set(member_ids) | {root.pk})
        cluster_count = len(cluster_members) + 1  # + this new report

    is_duplicate = duplicate_of is not None
    duplicate_count = cluster_count if is_duplicate else 0

    # -- severity ---------------------------------------------------------
    severity_level, severity_breakdown = score_severity(
        issue.category, issue.description, max(duplicate_count, 1)
    )

    # -- department routing -----------------------------------------------
    department = DEPARTMENT_BY_CATEGORY.get(issue.category, "General Services")

    analysis = {
        "engine": "rule-based-civic-analysis-v1",
        "engine_honest_label": "Rule-based analysis (not a trained ML model)",
        "duplicate": {
            "is_duplicate": is_duplicate,
            "similarity_score": similarity,
            "root_id": duplicate_of.pk if duplicate_of else None,
            "cluster_members": cluster_members,
            "duplicate_count": duplicate_count,
        },
        "severity": severity_breakdown,
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
        "analysis",
        "updated_at",
    ])

    # A later duplicate increases the *root's* severity & report count too.
    if duplicate_of is not None and duplicate_of.pk != issue.pk:
        # Whole cluster now = previously-known members + this new report.
        root_dup_count = len(cluster_members) + 1
        root_sev, _ = score_severity(
            duplicate_of.category, duplicate_of.description, root_dup_count
        )
        duplicate_of.duplicate_count = root_dup_count
        duplicate_of.severity = root_sev
        duplicate_of.save(update_fields=["duplicate_count", "severity", "updated_at"])
        analysis["duplicate"]["root_duplicate_count"] = root_dup_count

    return analysis


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