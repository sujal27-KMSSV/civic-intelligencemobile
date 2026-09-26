from rest_framework import serializers

from .models import Issue
from .validators import validate_issue_image
from .window import delete_window_expired


class IssueSerializer(serializers.ModelSerializer):
    """Flattened issue payload.

    The Flutter app reads these exact top-level keys on every issue endpoint
    (list, detail, my-reports and the submission response): id, image_url,
    description, latitude, longitude, address, status, created_at, updated_at,
    category, confidence, severity, duplicate, duplicate_count, department,
    priority, priority_label, master_id, cluster_size.
    """

    image = serializers.ImageField(
        write_only=True, required=True, validators=[validate_issue_image]
    )
    image_url = serializers.ImageField(source="image", read_only=True)
    image_source = serializers.ChoiceField(
        choices=Issue.ImageSource.choices,
        required=False,
        allow_blank=True,
    )
    # Client idempotency key: write-only, never exposed in responses. The view
    # uses it to return the existing report on a duplicate retry.
    client_request_id = serializers.CharField(
        required=False,
        allow_blank=True,
        allow_null=True,
        max_length=128,
        write_only=True,
    )
    description = serializers.CharField(required=False, allow_blank=True)
    latitude = serializers.FloatField(min_value=-90.0, max_value=90.0)
    longitude = serializers.FloatField(min_value=-180.0, max_value=180.0)
    category = serializers.ChoiceField(
        choices=Issue.Category.choices, required=False
    )
    confidence = serializers.FloatField(
        required=False, min_value=0.0, max_value=1.0
    )
    severity = serializers.ChoiceField(
        choices=Issue.Severity.choices, required=False
    )
    duplicate = serializers.BooleanField(required=False)
    duplicate_count = serializers.IntegerField(required=False, min_value=0)
    department = serializers.CharField(required=False, max_length=64)
    status = serializers.ChoiceField(
        choices=Issue.Status.choices, required=False
    )
    resolution_status = serializers.SerializerMethodField(read_only=True)
    resolution_image_url = serializers.ImageField(
        source="resolution_image", read_only=True
    )
    resolution_similarity = serializers.FloatField(read_only=True)
    resolved_at = serializers.DateTimeField(read_only=True)
    # Explainable priority (rule-based, 0..100) surfaced to the app.
    priority = serializers.FloatField(read_only=True)
    priority_label = serializers.CharField(read_only=True)
    priority_reasons = serializers.JSONField(read_only=True)
    # Duplicate-cluster context: which report is the cluster master, and (for
    # the master) the ids of the supporting reports it consolidates.
    master_id = serializers.SerializerMethodField(read_only=True)
    is_master = serializers.SerializerMethodField(read_only=True)
    cluster_size = serializers.SerializerMethodField(read_only=True)
    cluster_member_ids = serializers.SerializerMethodField(read_only=True)
    # Server-authoritative retraction/editing flags. The app derives Delete /
    # Edit visibility exclusively from these, eliminating device-vs-server
    # clock skew (the historical cause of the "Delete button flicker" bug).
    can_delete = serializers.SerializerMethodField(read_only=True)
    can_edit = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = Issue
        fields = [
            "id",
            "image",
            "image_url",
            "image_source",
            "client_request_id",
            "description",
            "latitude",
            "longitude",
            "address",
            "status",
            "created_at",
            "updated_at",
            "category",
            "confidence",
            "severity",
            "duplicate",
            "duplicate_count",
            "duplicate_of",
            "department",
            "priority",
            "priority_label",
            "priority_reasons",
            "master_id",
            "is_master",
            "cluster_size",
            "cluster_member_ids",
            "resolution_status",
            "resolution_image_url",
            "resolution_similarity",
            "resolved_at",
            "can_delete",
            "can_edit",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    def get_resolution_status(self, obj) -> str:
        if obj.status == Issue.Status.RESOLVED:
            return "resolved"
        if obj.resolution_similarity is not None:
            return "verification-recorded"
        return "pending"

    def get_master_id(self, obj):
        # A duplicate points at its cluster master; a master is its own master.
        return obj.duplicate_of_id if obj.duplicate_of_id is not None else obj.pk

    def get_is_master(self, obj) -> bool:
        # A "master" consolidates at least one supporting report.
        return obj.duplicate_of_id is None and obj.duplicate_count > 0

    def get_cluster_size(self, obj) -> int:
        if obj.duplicate_of_id is not None:
            return max(1, obj.duplicate_of_id and (obj.duplicate_count or 1))
        return max(1, obj.duplicate_count or 1)

    def get_cluster_member_ids(self, obj) -> list:
        # Only the master reports the full member list (children reference it).
        if obj.duplicate_of_id is not None or obj.pk is None:
            return []
        return sorted(
            {obj.pk} | {d.pk for d in obj.duplicates.all()}
        )

    def get_can_delete(self, obj) -> bool:
        return not delete_window_expired(obj.created_at)

    def get_can_edit(self, obj) -> bool:
        # Editing the report text stays possible while the report is visible.
        # Only the coordinator may update the working description after the
        # status moves out of REPORTED, so citizens stop editing then.
        return obj.status in (Issue.Status.REPORTED, Issue.Status.VERIFIED)