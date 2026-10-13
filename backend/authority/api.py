"""Authority REST API (staff-only JSON endpoints).

All endpoints require an authenticated IS_STAFF user (token or session).
"""

from __future__ import annotations

import re

from django.db.models import Case, F, IntegerField, Value, When
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from issues.lifecycle import VALID_TRANSITIONS
from issues.models import Issue
from issues.spatial import describe_spatial_backend

from . import service
from .serializers import AuthorityIssueSerializer

SEVERITY_RANK = {
    "critical": 0,
    "high": 1,
    "medium": 2,
    "low": 3,
}
OPEN_STATUSES = ["reported", "verified", "assigned", "in_progress"]

_VALID_STATUSES = {value for value, _label in Issue.Status.choices}
_VALID_SEVERITIES = {value for value, _label in Issue.Severity.choices}
_VALID_CATEGORIES = {value for value, _label in Issue.Category.choices}
_VALID_PRIORITY_CLASSES = {"low", "medium", "high", "critical"}


def _bad_request(detail, **extra) -> Response:
    payload = {"detail": detail}
    payload.update(extra)
    return Response(payload, status=status.HTTP_400_BAD_REQUEST)


def _order_spec(ordering: str) -> tuple[str, ...]:
    """Whitelisted sort specs. Mirrors service.ORDERING_KEYS."""
    return {
        "priority": ("-priority", "created_at"),
        "newest": ("-created_at",),
        "oldest": ("created_at",),
        "cluster": ("-cluster_rank", "-priority", "created_at"),
        "severity": ("-severity_rank", "-priority", "created_at"),
        "reports": ("-duplicate_count", "-priority", "created_at"),
        "status": ("is_open", "status", "-priority", "created_at"),
    }[ordering]


def _apply_filters(request):
    """Build the filtered/annotated query-set from query params.

    Raises ``ValueError`` on any unknown filter value (the console relies on
    the backend rejecting unknown values so it cannot drift out of sync).
    """
    qs = Issue.objects.all().select_related("duplicate_of", "reporter", "assigned_to")

    scope = request.query_params.get("scope", "masters")
    if scope == "masters":
        qs = qs.filter(duplicate_of__isnull=True)
    elif scope == "supporting":
        qs = qs.filter(duplicate_of__isnull=False)
    elif scope != "all":
        raise ValueError(
            f"Unknown scope: {scope!r}. Valid scopes: {', '.join(service.SCOPES)}"
        )

    status_f = request.query_params.get("status")
    if status_f:
        if status_f not in _VALID_STATUSES:
            raise ValueError(f"Unknown status: {status_f!r}.")
        qs = qs.filter(status=status_f)
    severity_f = request.query_params.get("severity")
    if severity_f:
        if severity_f not in _VALID_SEVERITIES:
            raise ValueError(f"Unknown severity: {severity_f!r}.")
        qs = qs.filter(severity=severity_f)
    category_f = request.query_params.get("category")
    if category_f:
        if category_f not in _VALID_CATEGORIES:
            raise ValueError(f"Unknown category: {category_f!r}.")
        qs = qs.filter(category=category_f)
    priority_f = request.query_params.get("priority_class")
    if priority_f:
        if priority_f not in _VALID_PRIORITY_CLASSES:
            raise ValueError(
                f"Unknown priority_class: {priority_f!r}. "
                "Valid classes: low, medium, high, critical."
            )
        qs = qs.filter(priority_label=priority_f)
    assigned_f = request.query_params.get("assigned")
    if assigned_f in ("assigned", "unassigned"):
        qs = qs.filter(
            assigned_to__isnull=assigned_f != "assigned"
        )
    elif assigned_f:
        raise ValueError(
            "assigned must be 'assigned' or 'unassigned'."
        )
    dept_f = request.query_params.get("department")
    if dept_f:
        qs = qs.filter(department=dept_f)

    priority_min = request.query_params.get("priority_min")
    if priority_min is not None:
        qs = qs.filter(priority__gte=float(priority_min))
    priority_max = request.query_params.get("priority_max")
    if priority_max is not None:
        qs = qs.filter(priority__lte=float(priority_max))

    created_after = request.query_params.get("created_after")
    if created_after:
        qs = qs.filter(created_at__date__gte=created_after)
    created_before = request.query_params.get("created_before")
    if created_before:
        qs = qs.filter(created_at__date__lte=created_before)

    def _int(name):
        value = request.query_params.get(name)
        return float(value) if value is not None else None

    lat_min, lat_max = _int("lat_min"), _int("lat_max")
    if lat_min is not None and lat_max is not None:
        qs = qs.filter(latitude__range=(lat_min, lat_max))
    lon_min, lon_max = _int("lon_min"), _int("lon_max")
    if lon_min is not None and lon_max is not None:
        qs = qs.filter(longitude__range=(lon_min, lon_max))

    q_value = (request.query_params.get("q") or "").strip()
    if q_value:
        from django.db.models import Q

        text_q = Q(description__icontains=q_value) | Q(address__icontains=q_value)
        qs = qs.filter(text_q | Q(reporter__email__icontains=q_value))
        if re.fullmatch(r"\d+", q_value):
            qs = qs.filter(Q(pk=int(q_value)) | Q(duplicate_of_id=int(q_value)))

    if not request.query_params.get("include_resolved"):
        qs = qs.exclude(status__in=["resolved", "rejected"])

    return qs.annotate(
        is_open=Case(
            When(status__in=OPEN_STATUSES, then=Value(0)),
            default=Value(1),
            output_field=IntegerField(),
        ),
        severity_rank=Case(
            *[When(severity=value, then=Value(rank)) for value, rank in SEVERITY_RANK.items()],
            default=Value(9),
            output_field=IntegerField(),
        ),
        cluster_rank=Case(
            When(duplicate_of__isnull=True, then=F("duplicate_count")),
            default=Value(1),
            output_field=IntegerField(),
        ),
    )


def _parse_pagination(request):
    """(page, page_size) from query params, or None (no pagination requested).

    Raises ``ValueError`` on malformed/unbounded values.
    """
    page_raw = request.query_params.get("page")
    if page_raw is None:
        return None
    try:
        page = int(page_raw)
    except (TypeError, ValueError):
        raise ValueError("page must be an integer.")
    if page < 1:
        raise ValueError("page must be >= 1.")
    try:
        page_size = int(request.query_params.get("page_size", "25"))
    except (TypeError, ValueError):
        raise ValueError("page_size must be an integer.")
    page_size = max(1, min(page_size, 100))
    return page, page_size


def _paginate(request, qs, serializer):
    pagination = _parse_pagination(request)
    count = qs.count()
    if pagination is None:
        return Response(serializer(qs, many=True).data)
    page, page_size = pagination
    total_pages = (count + page_size - 1) // page_size
    start = (page - 1) * page_size
    return Response(
        {
            "count": count,
            "page": page,
            "page_size": page_size,
            "total_pages": total_pages,
            "results": serializer(qs[start : start + page_size], many=True).data,
        }
    )


@api_view(["GET"])
@permission_classes([permissions.IsAdminUser])
def issue_list(request):
    """List issues with server-side filtering, sorting and pagination.

    Query params: ``?scope=`` (masters|supporting|all, default masters),
    ``?status=`` ``?severity=`` ``?category=`` ``?priority_class=``
    ``?department=`` ``?assigned=`` (assigned|unassigned),
    ``?q=`` ``?priority_min=`` ``?priority_max=`` ``?created_after=``
    ``?created_before=`` ``?lat_min=``/``?lat_max=``/``?lon_min=``/``?lon_max=``,
    ``?include_resolved=1`` (default hides resolved/rejected),
    ``?ordering=`` (priority|newest|oldest|cluster|severity|reports|status).
    Supplying ``?page=`` opts into the paginated envelope
    ``{count, page, page_size, total_pages, results}``; without it a plain
    array is returned.
    """
    try:
        qs = _apply_filters(request)
    except ValueError as exc:
        return _bad_request(str(exc))
    ordering = request.query_params.get("ordering", "priority")
    if ordering not in service.ORDERING_KEYS:
        return _bad_request(
            f"Unknown ordering: {ordering!r}. Valid orderings: "
            f"{', '.join(service.ORDERING_KEYS)}"
        )
    qs = qs.order_by(*_order_spec(ordering))

    try:
        return _paginate(request, qs, AuthorityIssueSerializer)
    except ValueError as exc:
        return _bad_request(str(exc))


@api_view(["GET", "PATCH"])
@permission_classes([permissions.IsAdminUser])
def issue_detail(request, pk):
    """GET: full authority view of an issue + current duplicate cluster.

    PATCH: staff dispatch — body ``{"department": str}`` and/or
    ``{"officer_id": int | null}`` (null unassigns). Unknown departments or
    non-staff officer ids are rejected with a 400.
    """
    try:
        issue = (
            Issue.objects.select_related("duplicate_of", "reporter", "assigned_to")
            .prefetch_related("duplicates")
            .get(pk=pk)
        )
    except Issue.DoesNotExist:
        return Response({"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND)

    if request.method == "PATCH":
        department = request.data.get("department", service.MISSING)
        officer_raw = request.data.get("officer_id", service.MISSING)
        officer_id = officer_raw
        if officer_id is not service.MISSING and officer_id is not None:
            try:
                officer_id = int(officer_id)
            except (TypeError, ValueError):
                return _bad_request(f"Unknown staff officer id: {officer_raw!r}.")
        issue, error = service.apply_assignment(
            issue, department=department, officer_id=officer_id
        )
        if error is not None:
            return Response(error, status=status.HTTP_400_BAD_REQUEST)
        return Response(AuthorityIssueSerializer(issue).data)

    root = issue.duplicate_of or issue
    cluster_ids = sorted(
        {root.pk} | set(root.duplicates.values_list("pk", flat=True)) | {issue.pk}
    )
    cluster_map = {
        item.pk: item
        for item in Issue.objects.select_related("reporter").filter(pk__in=cluster_ids)
    }
    allowed = sorted(
        target
        for target in VALID_TRANSITIONS.get(issue.status, set())
        if target != Issue.Status.RESOLVED
    )
    data = AuthorityIssueSerializer(issue).data
    data["cluster"] = [
        AuthorityIssueSerializer(cluster_map[_id]).data for _id in cluster_ids
    ]
    data["master"] = AuthorityIssueSerializer(root).data
    data["allowed_transitions"] = allowed
    return Response(data)


@api_view(["POST"])
@permission_classes([permissions.IsAdminUser])
def issue_transition(request, pk):
    """Change lifecycle status. Body: ``{"new_status": "verified"}``."""
    try:
        issue = Issue.objects.get(pk=pk)
    except Issue.DoesNotExist:
        return Response({"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND)

    new_status = request.data.get("new_status")
    issue, error = service.transition_issue(issue, new_status)
    if error:
        return Response({"detail": error}, status=status.HTTP_400_BAD_REQUEST)
    return Response(AuthorityIssueSerializer(issue).data)


@api_view(["POST"])
@permission_classes([permissions.IsAdminUser])
def issue_resolve(request, pk):
    """Upload resolution evidence (multipart: ``image`` + optional ``notes``)."""
    try:
        issue = Issue.objects.get(pk=pk)
    except Issue.DoesNotExist:
        return Response({"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND)

    image_file = request.FILES.get("image")
    notes = request.data.get("notes", "")
    issue, similarity, error = service.resolve_issue(issue, image_file, notes)
    if error:
        return Response({"detail": error}, status=status.HTTP_400_BAD_REQUEST)
    return Response(
        {
            **AuthorityIssueSerializer(issue).data,
            "image_similarity": similarity,
        }
    )


@api_view(["GET"])
@permission_classes([permissions.IsAdminUser])
def stats(request):
    """Aggregate counters + hotspot analytics for the dashboard."""
    data = service.console_stats()
    data["analytics"] = service.analytics()
    return Response(data)


@api_view(["GET"])
@permission_classes([permissions.IsAdminUser])
def hotspot_cells(request):
    """Priority-ordered hotspot cells for the authority heat map.

    Includes resolved/rejected statuses in the aggregates so the authority can
    see recent history, not just what is open right now. ``?grid=`` tunes cell
    size; ``?limit=`` caps the number of cells; ``?category=`` narrows the
    dataset. Returns the console's envelope with an honest spatial-backend
    probe attached.
    """
    from issues import civic as issues_civic

    try:
        grid = float(request.query_params.get("grid", 0.002))
        if not (0.0001 <= grid <= 0.05):
            raise ValueError
    except ValueError:
        return Response(
            {"detail": "grid must be a number of degrees between 0.0001 and 0.05."},
            status=status.HTTP_400_BAD_REQUEST,
        )
    limit = max(1, min(int(request.query_params.get("limit", 10) or 10), 50))
    qs = Issue.objects.all()
    category = request.query_params.get("category")
    if category:
        if category not in _VALID_CATEGORIES:
            return _bad_request(f"Unknown category: {category!r}.")
        qs = qs.filter(category=category)
    cells = issues_civic.cluster_hotspots(qs, grid=grid, limit=limit)
    total_masters = (
        qs.filter(duplicate_of__isnull=True)
        .exclude(status__in=["resolved", "rejected"])
        .count()
    )
    return Response(
        {
            "hotspots": cells,
            "total_masters": total_masters,
            "method": "grid_aggregation",
            "method_honest_label": (
                "Counts of real reports grouped into a fixed geographic grid. "
                "This is an aggregation, not a learned anomaly model."
            ),
            "spatial_backend": describe_spatial_backend(),
            "returned": len(cells),
            "limit": limit,
        }
    )


@api_view(["GET"])
@permission_classes([permissions.IsAdminUser])
def meta(request):
    """Immutable-per-deployment metadata for the React console."""
    return Response(service.meta())