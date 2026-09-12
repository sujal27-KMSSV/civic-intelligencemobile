"""Authority REST API (staff-only JSON endpoints).

All endpoints require an authenticated IS_STAFF user (token or session).
"""

from __future__ import annotations

from django.db.models import Case, IntegerField, Value, When
from rest_framework import permissions, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response

from issues.models import Issue

from . import service
from .serializers import AuthorityIssueSerializer

SEVERITY_RANK = {
    "critical": 0,
    "high": 1,
    "medium": 2,
    "low": 3,
}
OPEN_STATUSES = ["reported", "verified", "assigned", "in_progress"]


@api_view(["GET"])
@permission_classes([permissions.IsAdminUser])
def issue_list(request):
    """List issues, unresolved first (then critical first, then oldest).

    Query params: ``?status=`` ``?severity=`` ``?department=``
    ``?include_resolved=1`` (default hides resolved/rejected).
    """
    qs = Issue.objects.all()
    status_f = request.query_params.get("status")
    severity_f = request.query_params.get("severity")
    dept_f = request.query_params.get("department")
    if status_f:
        qs = qs.filter(status=status_f)
    if severity_f:
        qs = qs.filter(severity=severity_f)
    if dept_f:
        qs = qs.filter(department=dept_f)
    if not request.query_params.get("include_resolved"):
        qs = qs.exclude(status__in=["resolved", "rejected"])

    qs = qs.annotate(
        is_open=Case(
            When(status__in=OPEN_STATUSES, then=Value(0)),
            default=Value(1),
            output_field=IntegerField(),
        )
    ).order_by("is_open", "created_at")
    return Response(AuthorityIssueSerializer(qs, many=True).data)


@api_view(["GET"])
@permission_classes([permissions.IsAdminUser])
def issue_detail(request, pk):
    """Full authority view of an issue + its current duplicate cluster."""
    try:
        issue = Issue.objects.prefetch_related("duplicates").get(pk=pk)
    except Issue.DoesNotExist:
        return Response({"detail": "Not found."}, status=status.HTTP_404_NOT_FOUND)

    root = issue
    if issue.duplicate_of_id is not None:
        root = issue.duplicate_of
    cluster_ids = sorted(
        {root.pk}
        | set(root.duplicates.values_list("pk", flat=True))
        | {issue.pk}
    )
    data = AuthorityIssueSerializer(issue).data
    data["cluster"] = [
        AuthorityIssueSerializer(Issue.objects.get(pk=_id)).data
        for _id in cluster_ids
    ]
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
    """Aggregate counters for the dashboard."""
    data = service.stats_with_departments()
    data.pop("_", None)
    return Response(data)