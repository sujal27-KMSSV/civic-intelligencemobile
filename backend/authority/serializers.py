"""Authority-facing serializers (full analysis + resolution payload)."""

from rest_framework import serializers

from issues.models import Issue


class AuthorityIssueSerializer(serializers.ModelSerializer):
    image_url = serializers.ImageField(source="image", read_only=True)
    resolution_image_url = serializers.ImageField(
        source="resolution_image", read_only=True
    )
    analysis = serializers.JSONField(read_only=True)
    reporter_email = serializers.EmailField(
        source="reporter.email", read_only=True
    )

    class Meta:
        model = Issue
        fields = [
            "id",
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
            "duplicate_of",
            "department",
            "analysis",
            "reporter_email",
            "resolution_image_url",
            "resolution_notes",
            "resolution_similarity",
            "resolved_at",
        ]
        read_only_fields = fields


class DuplicateListSerializer(serializers.ModelSerializer):
    class Meta:
        model = Issue
        fields = ["id", "status", "created_at", "reporter_id"]