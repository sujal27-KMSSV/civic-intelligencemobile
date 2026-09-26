from django.db import IntegrityError, transaction
from rest_framework import generics, permissions, status, viewsets
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import PermissionDenied
from rest_framework.response import Response

from . import civic
from .lifecycle import validate_transition
from .models import Issue
from .serializers import IssueSerializer
from .window import DELETE_WINDOW_MESSAGE, delete_window_expired


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

    - GET    /api/issues/          public list, newest first; duplicates are
                                   COLLAPSED into their master issue by default
                                   (``?collapse=0`` returns every report)
    - GET    /api/issues/{id}/     public detail (with cluster context)
    - POST   /api/issues/          authenticated citizen submission (multipart)
    - PATCH  /api/issues/{id}/     reporter or staff update
    - DELETE /api/issues/{id}/     reporter or staff delete
    """

    queryset = Issue.objects.all().order_by("-priority", "-created_at")
    serializer_class = IssueSerializer
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_queryset(self):
        qs = (
            Issue.objects.all()
            .select_related("duplicate_of")
            .prefetch_related("duplicates")
        )
        if self.action == "list":
            collapse = self.request.query_params.get("collapse", "1")
            if collapse != "0":
                # MASTER-ISSUE CONSOLIDATION: the public feed shows one card per
                # cluster (the master), never the supporting duplicates. The
                # duplicate_count on the master card tells citizens how many
                # neighbours reported the same issue.
                qs = qs.filter(duplicate_of__isnull=True).order_by(
                    "-priority", "-created_at"
                )
            else:
                qs = qs.order_by("-created_at")
        return qs

    def get_permissions(self):
        if self.action in {"create", "partial_update", "destroy"}:
            return [permissions.IsAuthenticated(), IsOwnerOrStaff()]
        return [permissions.AllowAny()]

    def perform_delete_cleanup(self, issue):
        """Remove stored media for a deleted report."""
        for field in (issue.image, issue.resolution_image):
            if field:
                field.delete(save=False)

    def create(self, request, *args, **kwargs):
        """Create a report, de-duplicating retries that carry an idempotency key.

        A client that already submitted (and lost the response) re-posts with
        the SAME ``client_request_id``. Instead of creating a second report we
        return the original record as HTTP 200, so the mobile user never sees a
        duplicate after a tap that "looked like" it didn't go through.
        """
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        # Normalise absent keys to NULL so the partial unique constraint stays
        # happy across the (common) id-less reports.
        request_id = (
            (serializer.validated_data.get("client_request_id") or "").strip()
            or None
        )
        serializer.validated_data["client_request_id"] = request_id

        if request_id:
            existing = self._existing_by_request_id(request.user, request_id)
            if existing is not None:
                return Response(
                    IssueSerializer(existing).data, status=status.HTTP_200_OK
                )

        try:
            # The transaction + IntegrityError fallback makes the check atomic
            # even when two identical requests land concurrently.
            with transaction.atomic():
                self.perform_create(serializer)
        except IntegrityError:
            existing = self._existing_by_request_id(request.user, request_id)
            if existing is not None:
                return Response(
                    IssueSerializer(existing).data, status=status.HTTP_200_OK
                )
            raise

        headers = self.get_success_headers(serializer.data)
        return Response(
            serializer.data, status=status.HTTP_201_CREATED, headers=headers
        )

    def _existing_by_request_id(self, user, request_id):
        if not request_id:
            return None
        return (
            Issue.objects.filter(reporter=user, client_request_id=request_id)
            .select_related("reporter")
            .first()
        )

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
                "image_source",
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

        # The idempotency key is only meaningful at creation time; never let an
        # update mutate it.
        serializer.validated_data.pop("client_request_id", None)

        incoming = set(serializer.validated_data.keys())
        if not is_staff:
            # Citizens may only fix their own report's description/address.
            # Anything else (coordinates, category, photo, authority-owned
            # pipeline fields) would let a reporter overwrite analysis results
            # or claim a fake location, so it is rejected outright.
            disallowed = incoming - REPORTER_EDITABLE_FIELDS
            if disallowed:
                raise PermissionDenied(
                    "Citizens may only change: description, address. "
                    "Not allowed: " + ", ".join(sorted(disallowed))
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
        # RULE 4: the window is enforced here, server-side, on every delete —
        # even a manual DELETE request after expiry is rejected.
        if delete_window_expired(instance.created_at):
            raise PermissionDenied(DELETE_WINDOW_MESSAGE)

        # RULE 12: never leave a duplicate cluster corrupted. A deleted report
        # is either a duplicate (its root must be recomputed) or a root (its
        # orphaned duplicates must be re-rooted) — both handled before the row
        # and its media are removed.
        if instance.duplicate_of_id is not None:
            root = instance.duplicate_of
            self.perform_delete_cleanup(instance)
            instance.delete()
            civic.recompute_root_after_child_removal(root)
        else:
            children = list(instance.duplicates.order_by("created_at"))
            self.perform_delete_cleanup(instance)
            instance.delete()
            if children:
                civic.reroot_cluster_after_root_removal(children)


class MyReportsView(generics.ListAPIView):
    """The authenticated citizen's own reports, newest first."""

    serializer_class = IssueSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        return (
            Issue.objects.filter(reporter=self.request.user)
            .select_related("duplicate_of")
            .prefetch_related("duplicates")
            .order_by("-created_at")
        )


@api_view(["GET"])
@permission_classes([permissions.AllowAny])
def hotspots(request):
    """Heat-map cells computed from REAL open-issue locations (no model).

    Grid-buckets open issues (~220 m cells by default) and returns the densest
    cells so the app can render a civic-intelligence heat map. ``?grid=`` tunes
    cell size (degrees), ``?limit=`` caps the number of cells returned.
    """
    try:
        grid = float(request.query_params.get("grid", 0.002))
        if not (0.0001 <= grid <= 0.05):
            raise ValueError
    except ValueError:
        return Response(
            {"detail": "grid must be a number of degrees between 0.0001 and 0.05."},
            status=status.HTTP_400_BAD_REQUEST,
        )
    limit = max(1, min(int(request.query_params.get("limit", 5) or 5), 25))
    qs = Issue.objects.exclude(status__in=("resolved", "rejected"))
    return Response(civic.cluster_hotspots(qs, grid=grid, limit=limit))