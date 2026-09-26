"""Genuine PostGIS spatial sidecar (requires PostgreSQL + PostGIS + GDAL).

This app is ONLY registered in ``INSTALLED_APPS`` when the runtime genuinely
has a PostGIS database (``DB_ENGINE=postgresql`` and ``GEOSPAT_ENABLED=1``).
On databases without spatial support these models/endpoints do not exist and
the civic engine's pure-Python haversine logic remains the duplicate-detection
path -- an honest capability boundary rather than an emulated one. The geospat
test-suite therefore skips entirely when the capability is not enabled.
"""

from django.contrib.gis.db import models


class SpatialLocation(models.Model):
    """One indexed location row per issue, projected for metric queries.

    ``geography=True`` makes the field store geodesic (spherical) coordinates,
    so ``ST_DWithin`` / ``ST_Distance`` work natively in meters instead of
    degrees (matches PostGIS best practice for city-scale data).
    """

    issue = models.OneToOneField(
        "issues.Issue",
        on_delete=models.CASCADE,
        related_name="spatial",
    )
    point = models.PointField(srid=4326, geography=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):  # pragma: no cover - debug aid only
        return f"spatial#{self.issue_id} @ {self.point}"