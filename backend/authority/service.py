"""Shared authority operations (used by both the JSON API and the dashboard).

Keeps lifecycle + resolution logic in ONE place so the two front-ends behave
identically.
"""

from __future__ import annotations

from datetime import timedelta

from django.utils import timezone

from issues import civic as issues_civic
from issues.lifecycle import validate_transition
from issues.models import Issue


def transition_issue(issue: Issue, new_status: str | None) -> tuple[Issue, str | None]:
    """Apply a lifecycle transition, returning ``(issue, error_or_None)``.

    Moving a status TO ``resolved`` is intentionally not allowed here: the
    dedicated resolution endpoint enforces BEFORE/AFTER evidence first.
    """
    if not new_status:
        return issue, "A target status is required."
    if new_status == Issue.Status.RESOLVED:
        return issue, (
            "Resolving requires evidence: upload a 'completed' photo via the "
            "resolution action instead."
        )
    error = validate_transition(issue.status, new_status)
    if error:
        return issue, error

    issue.status = new_status
    if issue.status != Issue.Status.RESOLVED and issue.resolved_at:
        issue.resolved_at = None
    issue.save(update_fields=["status", "resolved_at", "updated_at"])
    return issue, None


def resolve_issue(
    issue: Issue, image_file, notes: str = ""
) -> tuple[Issue, dict, str | None]:
    """Resolve with BEFORE/AFTER image verification (honest heuristic).

    Allowed from ``in_progress`` or ``resolved`` (re-upload). Sets status to
    ``resolved`` and records the similarity measurement.

    Returns ``(issue, similarity_result, error_or_None)``.
    """
    if issue.status not in (
        Issue.Status.IN_PROGRESS,
        Issue.Status.RESOLVED,
    ):
        return issue, {}, (
            "The issue must be 'in progress' before it can be resolved."
        )
    if not image_file:
        return issue, {}, "A completion photo is required."

    issue.resolution_image = image_file
    issue.resolution_notes = notes or issue.resolution_notes
    issue.status = Issue.Status.RESOLVED
    issue.resolved_at = timezone.now()

    similarity = issues_civic.image_similarity(
        issue.image.name,
        issue.resolution_image.name,
    )
    if similarity.get("similarity") is not None:
        issue.resolution_similarity = similarity["similarity"]

    # Store the full honest measurement (method + interpretation + brightness)
    # on the row so the dashboard can show exactly how it was derived.
    analysis = dict(issue.analysis or {})
    analysis["resolution"] = {
        "method": similarity.get("method"),
        "similarity": similarity.get("similarity"),
        "interpretation": similarity.get("interpretation"),
        "brightness_before": similarity.get("brightness_before"),
        "brightness_after": similarity.get("brightness_after"),
        "note": (
            "Heuristic perceptual comparison of BEFORE/AFTER photos. "
            "Resolution remains an authority decision."
        ),
    }
    issue.analysis = analysis

    issue.save(update_fields=[
        "status",
        "resolution_image",
        "resolution_notes",
        "resolved_at",
        "resolution_similarity",
        "analysis",
        "updated_at",
    ])
    return issue, similarity, None


def stats() -> dict:
    """Dashboard statistics (one query per bucket; tiny dataset)."""
    now = timezone.now()
    qs = Issue.objects.all()
    return {
        "total": qs.count(),
        "by_status": {
            label: qs.filter(status=value).count()
            for value, label in Issue.Status.choices
        },
        "by_severity": {
            label: qs.filter(severity=value).count()
            for value, label in Issue.Severity.choices
        },
        "by_department": {},
        "open": qs.exclude(status__in=["resolved", "rejected"]).count(),
        "duplicates": qs.filter(duplicate=True).count(),
        "reported_today": qs.filter(
            created_at__gte=now - timedelta(hours=24)
        ).count(),
    }


def analytics() -> dict:
    """Hotspot + workload analytics computed from REAL issue data (no models).

    Deliberately small and honest: cells come from the same grid-bucket
    algorithm the mobile heat map uses; all counters are plain aggregate counts.
    """
    from issues import civic as issues_civic

    now = timezone.now()
    open_qs = Issue.objects.exclude(status__in=["resolved", "rejected"])

    hotspot_cells = issues_civic.cluster_hotspots(Issue.objects.all(), limit=8)

    # Open-report age in hours: median + oldest (points to SLA pressure).
    open_ages = []
    for issue in open_qs:
        if issue.created_at:
            open_ages.append((now - issue.created_at).total_seconds() / 3600.0)
    open_ages.sort()
    open_age_hours = {
        "count": len(open_ages),
        "median": round(open_ages[len(open_ages) // 2], 1) if open_ages else None,
        "oldest": round(open_ages[-1], 1) if open_ages else None,
    }

    clusters = Issue.objects.filter(duplicate_of__isnull=True)
    cluster_total = clusters.count()
    cluster_stats = {
        "clusters": cluster_total,
        "avg_members": round(
            (Issue.objects.count() / cluster_total) if cluster_total else 0.0,
            2,
        ),
        "consolidated_reports": Issue.objects.filter(duplicate=True).count(),
    }

    return {
        "hotspot_cells": hotspot_cells,
        "open_age_hours": open_age_hours,
        "cluster_stats": cluster_stats,
        "trend_reports": {
            "last_24h": Issue.objects.filter(created_at__gte=now - timedelta(hours=24)).count(),
            "last_48h": Issue.objects.filter(created_at__gte=now - timedelta(hours=48)).count(),
            "last_7d": Issue.objects.filter(created_at__gte=now - timedelta(days=7)).count(),
        },
    }


def _bucket_departments(stats_out: dict) -> None:
    qs = Issue.objects.all()
    for dept in (
        "Road Maintenance",
        "Solid Waste Management",
        "Public Lighting",
        "Drainage & Sewage",
        "General Services",
        "Unassigned",
    ):
        stats_out["by_department"][dept] = qs.filter(department=dept).count()


def stats_with_departments() -> dict:
    out = stats()
    _bucket_departments(out)
    return out