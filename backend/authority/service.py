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


# ---------------------------------------------------------------------------
# Extended authority-console contract (meta, console_stats, assignment).
# Kept separate from the legacy `stats()` shape above so the server-rendered
# dashboard keeps working while the React console gets the richer payload.
# ---------------------------------------------------------------------------

# Whitelisted list scopes + sort keys. The console sends these; anything else
# is rejected with a 400 so clients cannot drift out of sync with the contract.
SCOPES = ["masters", "supporting", "all"]
ORDERING_KEYS = ["priority", "newest", "oldest", "cluster", "severity", "reports", "status"]


def assignable_departments() -> list[str]:
    """Departments an officer may route to (routing table + any in use)."""
    from issues import civic as issues_civic

    return sorted(
        set(issues_civic.DEPARTMENT_BY_CATEGORY.values())
        | {"Unassigned"}
        | set(Issue.objects.values_list("department", flat=True).distinct())
    )


def _display_name(user) -> str:
    name = " ".join(p for p in (user.first_name, user.last_name) if p).strip()
    return name or user.email


def officers() -> list[dict]:
    from django.contrib.auth import get_user_model

    users = get_user_model().objects.filter(is_staff=True).order_by("email")
    return [
        {"id": u.id, "email": u.email, "name": _display_name(u)} for u in users
    ]


def vision_capability_report() -> dict:
    """What this Django deployment can genuinely claim about vision."""
    from issues import ai as issues_ai

    url = issues_ai.ai_service_url()
    configured = bool(url)
    return {
        "local_reference_path": {
            "available": True,
            "techniques": ["dhash-hamming-64", "mean-brightness"],
            "note": (
                "Perceptual hashing + mean-brightness comparison is pure Python "
                "and always available for duplicate detection and resolution "
                "verification."
            ),
            "honest_note": (
                "These are handcrafted heuristics, not a trained CLIP-style model."
            ),
        },
        "ai_service": {
            "configured": configured,
            "url": url or None,
            "reachable": False,
            "note": (
                "Reachability is probed per image at submission time (any "
                "failure falls back to the rule-based path); it is not checked "
                "by this endpoint."
                if configured
                else "No AI service is configured; the rule-based engine is "
                "authoritative."
            ),
        },
        "store_embeddings": True,
    }


def meta() -> dict:
    """Immutable-per-deployment metadata for the React console.

    Enums, assignable departments, staff officers, the lifecycle table and the
    capability probes. Read by ``GET /authority/meta/`` once per page load.
    """
    from issues import civic as issues_civic
    from issues.lifecycle import VALID_TRANSITIONS
    from issues.priority import priority_engine_info
    from issues.spatial import describe_spatial_backend

    def enum_options(choices):
        return [{"value": value, "label": str(label)} for value, label in choices]

    officer_list = officers()
    return {
        "departments": {
            "assignable": assignable_departments(),
            "by_category": dict(issues_civic.DEPARTMENT_BY_CATEGORY),
        },
        "categories": enum_options(Issue.Category.choices),
        "severities": enum_options(Issue.Severity.choices),
        "statuses": enum_options(Issue.Status.choices),
        "priority_classes": enum_options(Issue.Severity.choices),
        "ordering": list(ORDERING_KEYS),
        "scopes": list(SCOPES),
        "officers": officer_list,
        "officer_count": len(officer_list),
        "lifecycle": {
            "valid_transitions": {
                status_: sorted(targets) for status_, targets in VALID_TRANSITIONS.items()
            },
            "note": (
                "Status changes are validated against this table. Reaching "
                "'resolved' requires the dedicated resolution action with "
                "BEFORE/AFTER photo evidence."
            ),
        },
        "capabilities": {
            "spatial": describe_spatial_backend(),
            "vision": vision_capability_report(),
            "priority_engine": priority_engine_info(),
        },
    }


class _Missing:
    pass


MISSING = _Missing()


def apply_assignment(
    issue: Issue,
    *,
    department=MISSING,
    officer_id=MISSING,
) -> tuple[Issue, dict | None]:
    """Staff dispatch: route to a department and/or assign an officer.

    ``department``/``officer_id`` may be provided independently. ``officer_id``
    of ``None`` unassigns (the only way back to unassigned). Returns
    ``(issue, error_dict_or_None)`` — no row is saved when validation fails.
    """
    allowed = assignable_departments()
    if department is not MISSING:
        if not department or department not in allowed:
            return issue, {
                "detail": f"Unknown department: {department!r}.",
                "allowed": allowed,
            }
    if officer_id is not MISSING:
        if officer_id is None:
            pass
        else:
            from django.contrib.auth import get_user_model

            target = get_user_model().objects.filter(
                pk=int(officer_id), is_staff=True
            ).first()
            if target is None:
                return issue, {
                    "detail": f"Unknown staff officer id: {officer_id!r}.",
                }

    if department is not MISSING:
        issue.department = department
    if officer_id is not MISSING:
        if officer_id is None:
            issue.assigned_to = None
            issue.assigned_at = None
        else:
            issue.assigned_to_id = int(officer_id)
            issue.assigned_at = timezone.now()
    issue.save(
        update_fields=[
            "department",
            "assigned_to",
            "assigned_at",
            "updated_at",
        ]
    )
    return issue, None


def console_stats() -> dict:
    """The React console's Stats payload, computed from real authority rows.

    ``by_*`` buckets are keyed by the raw enum value (e.g. ``"reported"``) so
    the charts can index them directly. Master rows stand in for their whole
    cluster — the convention is stated in the payload itself.
    """
    from django.db.models import Count

    now = timezone.now()
    qs = Issue.objects.all()
    open_qs = qs.exclude(status__in=["resolved", "rejected"])
    masters = qs.filter(duplicate_of__isnull=True)
    open_masters = masters.exclude(status__in=["resolved", "rejected"])

    def tally(queryset, field):
        out = {}
        rows = queryset.values(field).annotate(n=Count("id"))
        for row in rows:
            key = row[field] or "unknown"
            out[key] = row["n"]
        return out

    department_names = sorted(
        n
        for n in open_qs.order_by()
        .values_list("department", flat=True)
        .distinct()
        if n
    )
    total_reports = qs.count()
    total_masters = masters.count()

    return {
        "active_issues": open_masters.count(),
        "critical_issues": open_masters.filter(
            severity=Issue.Severity.CRITICAL
        ).count(),
        "high_priority_issues": open_masters.filter(
            priority_label__in=["high", "critical"]
        ).count(),
        "resolved_issues": qs.filter(status=Issue.Status.RESOLVED).count(),
        "reports_consolidated": max(0, total_reports - total_masters),
        "active_departments": len(department_names),
        "total_masters": total_masters,
        "total_reports": total_reports,
        "total_reports_all_time": total_reports,
        "open_reports": open_qs.count(),
        "supporting_reports": max(0, total_reports - total_masters),
        "reported_last_24h": qs.filter(
            created_at__gte=now - timedelta(hours=24)
        ).count(),
        "resolved_last_24h": qs.filter(
            status=Issue.Status.RESOLVED, resolved_at__gte=now - timedelta(hours=24)
        ).count(),
        "assigned_open": open_masters.filter(assigned_to__isnull=False).count(),
        "unassigned_open": open_masters.filter(assigned_to__isnull=True).count(),
        "by_status": tally(qs, "status"),
        "by_open_status": tally(open_qs, "status"),
        "by_severity": tally(qs, "severity"),
        "by_priority_class": tally(qs, "priority_label"),
        "by_category": tally(qs, "category"),
        "by_department": tally(qs, "department"),
        "active_department_names": department_names,
        "counting_convention": (
            "Counted server-side from the authority database. One master row "
            "represents its whole cluster."
        ),
    }