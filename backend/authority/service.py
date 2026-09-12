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
        issues_civic.media_path(issue.image.name),
        issues_civic.media_path(issue.resolution_image.name),
    )
    if similarity.get("similarity") is not None:
        issue.resolution_similarity = similarity["similarity"]

    issue.save(update_fields=[
        "status",
        "resolution_image",
        "resolution_notes",
        "resolved_at",
        "resolution_similarity",
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