from rest_framework import generics, permissions, viewsets
from rest_framework.exceptions import PermissionDenied

from . import civic
from .lifecycle import validate_transition
from .models import Issue
from .serializers import IssueSerializer


class IsOwnerOrStaff(permissions.BasePermission):
    """Writes are allowed for the reporter (own content) or staff; reads fine."""

    def has_object_permission(self, request, view, obj):
        if request.method in permissions.SAFE_METHODS:
            return True
        return request.user.is_staff or obj.reporter_id == request.user.id


# Fields a citizen/reporter may edit on their own report.
REPORTER_EDITABLE_FIELDS = {"description", "address"}
# Fields nobody may edit through the citizen endpoint (authority-owned).
AUTHORITY_OWNED_FIELDS = {
    "status",
    "severity",
    "confidence",
    "duplicate",
    "duplicate_count",
    "duplicate_of",
    "department",
    "analysis",
    "resolution_image",
    "resolution_notes",
    "resolved_at",
    "resolution_similarity",
}


class IssueViewSet(viewsets.ModelViewSet):
    """Public read endpoints; authenticated writes.

    - GET    /api/issues/          public list, newest first
    - GET    /api/issues/{id}/     public detail
    - POST   /api/issues/          authenticated citizen submission (multipart)
    - PATCH  /api/issues/{id}/     reporter or staff update
    - DELETE /api/issues/{id}/     reporter or staff delete
    """

    queryset = Issue.objects.all().order_by("-created_at")
    serializer_class = IssueSerializer
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_permissions(self):
        if self.action in {"create", "partial_update", "destroy"}:
            return [permissions.IsAuthenticated(), IsOwnerOrStaff()]
        return [permissions.AllowAny()]

    def perform_delete_cleanup(self, issue):
        """Remove stored media for a deleted report."""
        for field in (issue.image, issue.resolution_image):
            if field:
                field.delete(save=False)

    def perform_create(self, serializer):
        # Civic-analysis fields are owned by the backend, never trusted from
        # the client. On creation, run the (honest, rule-based) analysis engine.
        validated_data = serializer.validated_data
        defaults = {
            "status": Issue.Status.REPORTED,
            "severity": Issue.Severity.LOW,
            "confidence": 0.0,
            "duplicate": False,
            "duplicate_count": 0,
            "department": "Unassigned",
        }
        client_fields = {
            key: validated_data[key]
            for key in (
                "image",
                "description",
                "latitude",
                "longitude",
                "address",
            )
            if key in validated_data
        }
        if "category" in validated_data:
            defaults["category"] = validated_data["category"]

        issue = serializer.save(
            reporter=self.request.user, **client_fields, **defaults
        )
        # Run civic intelligence (duplicate detection, severity, routing).
        civic.run_analysis(issue)

    def perform_update(self, serializer):
        issue = self.get_object()
        is_staff = self.request.user.is_staff
        if not (is_staff or issue.reporter_id == self.request.user.id):
            raise PermissionDenied("You do not have permission to perform this action.")

        incoming = set(serializer.validated_data.keys())
        if not is_staff:
            blocked = incoming & AUTHORITY_OWNED_FIELDS
            if blocked:
                raise PermissionDenied(
                    "Only the authority may change: "
                    + ", ".join(sorted(blocked))
                )
        else:
            # Staff may drive the lifecycle through this endpoint too; validate
            # the transition. (Authority resolves with the dedicated endpoint.)
            new_status = serializer.validated_data.get("status")
            if new_status:
                error = validate_transition(issue.status, new_status)
                if error:
                    from rest_framework.exceptions import ValidationError

                    raise ValidationError({"status": error})

        serializer.save()

    def perform_destroy(self, instance):
        self.perform_delete_cleanup(instance)
        instance.delete()


class MyReportsView(generics.ListAPIView):
    """The authenticated citizen's own reports, newest first."""

    serializer_class = IssueSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return (
            Issue.objects.filter(reporter=self.request.user)
            .select_related("reporter")
            .order_by("-created_at")
        )