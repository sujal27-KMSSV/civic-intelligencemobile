"""Authority-facing serializers (full analysis + resolution payload)."""

from __future__ import annotations

from rest_framework import serializers

from issues import civic as issues_civic
from issues.models import Issue


class AuthorityIssueSerializer(serializers.ModelSerializer):
    image_url = serializers.ImageField(source="image", read_only=True)
    resolution_image_url = serializers.ImageField(
        source="resolution_image", read_only=True
    )
    resolution_status = serializers.SerializerMethodField(read_only=True)
    analysis = serializers.JSONField(read_only=True)
    reporter_email = serializers.EmailField(
        source="reporter.email", read_only=True
    )
    vision = serializers.JSONField(read_only=True)
    priority_model_score = serializers.FloatField(read_only=True)
    # Staff dispatch fields (assigned_to is set via PATCH on the authority API).
    assigned_to = serializers.IntegerField(
        source="assigned_to_id", read_only=True
    )
    assigned_to_email = serializers.EmailField(
        source="assigned_to.email", read_only=True
    )
    assigned_to_name = serializers.SerializerMethodField(read_only=True)
    assigned_at = serializers.DateTimeField(read_only=True)
    # Duplicate-cluster context, mirroring the flattened public Issue payload.
    master_id = serializers.SerializerMethodField(read_only=True)
    is_master = serializers.SerializerMethodField(read_only=True)
    cluster_size = serializers.SerializerMethodField(read_only=True)
    cluster_member_ids = serializers.SerializerMethodField(read_only=True)
    # Consolidated-cluster explanation + the priority 'why' breakdown.
    duplicate_signals = serializers.SerializerMethodField(read_only=True)
    priority_explanation = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model = Issue
        fields = [
            "id",
            "image_url",
            "image_source",
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
            "assigned_to",
            "assigned_to_email",
            "assigned_to_name",
            "assigned_at",
            "priority",
            "priority_label",
            "priority_reasons",
            "priority_model_score",
            "priority_explanation",
            "duplicate_signals",
            "master_id",
            "is_master",
            "cluster_size",
            "cluster_member_ids",
            "analysis",
            "vision",
            "reporter_email",
            "resolution_status",
            "resolution_image_url",
            "resolution_notes",
            "resolution_similarity",
            "resolved_at",
        ]
        read_only_fields = fields

    def get_resolution_status(self, obj) -> str:
        if obj.status == Issue.Status.RESOLVED:
            return "resolved"
        if obj.resolution_similarity is not None:
            return "verification-recorded"
        return "pending"

    def get_assigned_to_name(self, obj):
        user = obj.assigned_to
        if user is None:
            return None
        name = " ".join(p for p in (user.first_name, user.last_name) if p).strip()
        return name or user.email

    def get_master_id(self, obj):
        return obj.duplicate_of_id if obj.duplicate_of_id is not None else obj.pk

    def get_is_master(self, obj) -> bool:
        return obj.duplicate_of_id is None and obj.duplicate_count > 0

    def get_cluster_size(self, obj) -> int:
        if obj.duplicate_of_id is not None:
            return max(1, (obj.duplicate_of_id and (obj.duplicate_count or 1)))
        return max(1, obj.duplicate_count or 1)

    def get_cluster_member_ids(self, obj) -> list:
        if obj.duplicate_of_id is not None:
            return []
        return sorted({obj.pk} | {d.pk for d in obj.duplicates.all()})

    def get_duplicate_signals(self, obj):
        """The per-signal consolidation breakdown the engine recorded.

        Only a *supporting* report carries ``analysis["duplicate"]["evidence"]``;
        masters and standalone reports get ``None`` so the UI says plainly that
        no breakdown was recorded rather than fabricating one.
        """
        dup = (obj.analysis or {}).get("duplicate") or {}
        evidence = dup.get("evidence") or []
        available = [e for e in evidence if e.get("value") is not None]
        if not available:
            return None

        weights = issues_civic.duplicate_weights()
        # What the engine ACTUALLY applied: static weights renormalized after
        # dropping signals that were unavailable for this comparison.
        denom = sum(weights.get(e["name"], 0.0) for e in available) or 1.0
        used_weights = {
            e["name"]: round(weights.get(e["name"], 0.0) / denom, 4)
            for e in available
        }
        return {
            "signals": {
                e["name"]: round(float(e["value"]), 4) for e in available
            },
            "weights": weights,
            "used_weights": used_weights,
            "similarity_score": (
                None
                if dup.get("similarity_score") is None
                else round(float(dup.get("similarity_score")), 4)
            ),
            "matched_report_id": None,
            "root_id": dup.get("root_id"),
        }

    def get_priority_explanation(self, obj):
        from issues.priority import build_priority_explanation

        return build_priority_explanation(obj)


class DuplicateListSerializer(serializers.ModelSerializer):
    class Meta:
        model = Issue
        fields = ["id", "status", "created_at", "reporter_id"]