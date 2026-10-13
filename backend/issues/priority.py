"""Explainable priority engine: compile-time catalogue + per-issue explanation.

This is the source of truth for *descriptions* of the priority engine that the
authority console displays:

* ``GET /authority/meta/`` serves ``priority_engine_info()`` (components,
  thresholds, weights, honest notes) so the UI's "how is this computed?"
  disclosure cannot drift from the scoring that actually runs
  (``civic.score_priority``).
* ``build_priority_explanation(issue)`` reconstructs the per-issue breakdown
  from the values the engine *actually stored* on the row. Nothing is scored
  here and nothing is invented: if the engine recorded no reasons, the payload
  says so.

The engine is a deterministic weighted RULE model, not a trained ML model; the
labels below state that plainly so the dashboard never presents it otherwise.
"""

from __future__ import annotations

from django.utils import timezone

from . import civic

# Same version string the analysis engine writes into ``Issue.analysis``.
PRIORITY_ENGINE = "rule-based-civic-analysis-v3"
PRIORITY_ENGINE_HONEST_LABEL = (
    "A transparent, deterministic weighted rule model. Every point comes from "
    "a named, auditable rule — not from a trained model."
)
PRIORITY_SCORE_MAX = 100

# Bands mirror civic.score_priority()'s thresholds exactly.
PRIORITY_CLASS_THRESHOLDS = [
    {"min_score": 0, "class": "low", "label": "Low"},
    {"min_score": 30, "class": "medium", "label": "Medium"},
    {"min_score": 55, "class": "high", "label": "High"},
    {"min_score": 80, "class": "critical", "label": "Critical"},
]

PRIORITY_COMPONENTS = [
    {
        "code": "severity",
        "label": "Severity base",
        "description": "Base points from the resolved severity level "
        "(low/medium/high/critical = 10/20/30/40).",
        "cap": civic.PRIORITY_SEVERITY_BASE["critical"],
    },
    {
        "code": "duplicate_reports",
        "label": "Supporting reports",
        "description": "Points for every citizen report beyond the first that "
        "describes the same physical problem.",
        "cap": civic.PRIORITY_DUP_MAX,
        "half_saturation": max(1, round(civic.PRIORITY_DUP_MAX / 2 / civic.PRIORITY_DUP_PER_REPORT)),
    },
    {
        "code": "reported_recently",
        "label": "Reported recently",
        "description": "Freshness points: full value within 24 hours, half "
        "value within 72 hours of the report.",
        "cap": civic.PRIORITY_FRESH_24H,
    },
    {
        "code": "cluster_master",
        "label": "Consolidated master",
        "description": "Bonus paid when the report is the master row that "
        "already consolidates several citizen reports.",
        "cap": civic.PRIORITY_MASTER_UPLIFT,
    },
]

COMPONENT_TOTAL_CAP = sum(component["cap"] for component in PRIORITY_COMPONENTS)

REASON_LABELS = {
    "severity": "Severity base",
    "duplicate_reports": "Supporting reports",
    "reported_recently": "Reported recently",
    "cluster_master": "Consolidated master",
}


def priority_engine_info() -> dict:
    """The compile-time catalogue served by ``GET /authority/meta/``."""
    return {
        "engine": PRIORITY_ENGINE,
        "engine_honest_label": PRIORITY_ENGINE_HONEST_LABEL,
        "score_range": [0, PRIORITY_SCORE_MAX],
        "class_thresholds": PRIORITY_CLASS_THRESHOLDS,
        "components": PRIORITY_COMPONENTS,
        "duplicate_signals": civic.duplicate_weights(),
        "component_total_cap": COMPONENT_TOTAL_CAP,
        "honest_note": (
            "Priority ranks how urgently an issue should be acted on. It is a "
            "deterministic weighted rule model, never a trained model, and it "
            "is separate from severity. Every point is traceable to the named "
            "component it came from."
        ),
    }


def _cluster_ids_and_days(issue) -> tuple[list[int], int]:
    """Ids of the whole duplicate cluster plus distinct report days.

    One query. A solo issue is its own one-member cluster with one day.
    """
    from .models import Issue  # local import to avoid circulars

    root = issue.duplicate_of or issue
    ids = sorted({root.pk} | set(root.duplicates.values_list("pk", flat=True)))
    if not ids:
        return [], 1
    qs = (
        Issue.objects.filter(pk__in=ids)
        .exclude(created_at__isnull=True)
        .values("created_at__date")
        .distinct()
    )
    return ids, qs.count() or 1


def build_priority_explanation(issue) -> dict:
    """Per-issue explanation built ONLY from what the engine stored.

    ``issue`` must be a saved ``Issue``. Raises no exceptions; if the row has
    no recorded reasons the payload is still structurally complete so the
    front-end can decide how to phrase the absence.
    """
    reasons_raw = issue.priority_reasons or []
    reasons: list[dict] = []
    components: dict[str, float] = {}
    raw_total = 0.0
    for entry in reasons_raw:
        if not isinstance(entry, dict):
            continue
        code = entry.get("factor")
        if not code:
            continue
        points = float(entry.get("points") or 0.0)
        raw_total += points
        components[code] = round(components.get(code, 0.0) + points, 1)
        reasons.append(
            {
                "code": code,
                "label": REASON_LABELS.get(code, code.replace("_", " ").title()),
                "points": points,
                "detail": entry.get("note") or "",
            }
        )

    analysis = issue.analysis or {}
    live_now = timezone.now()
    start = issue.created_at
    end = issue.resolved_at if issue.resolved_at is not None else live_now
    open_hours = (
        round((end - start).total_seconds() / 3600.0, 1)
        if start is not None
        else None
    )
    _ids, distinct_days = _cluster_ids_and_days(issue)

    prior_reports = 0
    if start is not None:
        from .models import Issue as _Issue

        prior_reports = _Issue.objects.filter(
            latitude__range=(
                float(issue.latitude) - 0.002,
                float(issue.latitude) + 0.002,
            ),
            longitude__range=(
                float(issue.longitude) - 0.002,
                float(issue.longitude) + 0.002,
            ),
            created_at__lt=start,
        ).exclude(pk=issue.pk).count()

    return {
        "score": round(float(issue.priority or 0.0), 1),
        "class": issue.priority_label or "low",
        "label": issue.priority_label or "low",
        "engine": analysis.get("engine") or PRIORITY_ENGINE,
        "engine_honest_label": (
            analysis.get("engine_honest_label") or PRIORITY_ENGINE_HONEST_LABEL
        ),
        "reasons": reasons,
        "components": components,
        "raw_total": round(raw_total, 1),
        "inputs": {
            "category": issue.category,
            "severity": issue.severity,
            "cluster_size": max(1, issue.duplicate_count or 1),
            "distinct_report_days": distinct_days,
            "open_hours": open_hours,
            "mean_similarity": (
                round(float(issue.confidence or 0.0), 4)
                if issue.duplicate_of_id is not None
                else None
            ),
            "prior_reports_at_location": prior_reports,
        },
    }