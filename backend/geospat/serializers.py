from rest_framework import serializers

from issues.serializers import IssueSerializer


class NearbyResultSerializer(serializers.Serializer):
    """A real PostGIS distance plus the full civic issue payload."""

    distance_m = serializers.FloatField()
    issue = IssueSerializer()