from rest_framework import serializers

from .models import Issue
from .validators import validate_issue_image


class IssueSerializer(serializers.ModelSerializer):
    """Flattened issue payload.

    The Flutter app reads these exact top-level keys on every issue endpoint
    (list, detail, my-reports and the submission response): id, image_url,
    description, latitude, longitude, address, status, created_at, updated_at,
    category, confidence, severity, duplicate, duplicate_count, department.
    """

    image = serializers.ImageField(
        write_only=True, required=True, validators=[validate_issue_image]
    )
    image_url = serializers.ImageField(source="image", read_only=True)
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

    class Meta:
        model = Issue
        fields = [
            "id",
            "image",
            "image_url",
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
            "department",
            "resolution_status",
            "resolution_image_url",
            "resolution_similarity",
            "resolved_at",
        ]
        read_only_fields = ["id", "created_at", "updated_at"]

    def get_resolution_status(self, obj) -> str:
        if obj.status == Issue.Status.RESOLVED:
            return "resolved"
        if obj.resolution_similarity is not None:
            return "verification-recorded"
        return "pending"