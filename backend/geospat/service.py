"""Coordinate helpers and genuine PostGIS queries for the geospat sidecar.

Nothing here emulates PostGIS: every query runs on the real ``ST_DWithin`` /
``ST_Distance`` SQL when the capability is present. Callers on non-spatial
databases never reach this module because the app is not installed there.

GDAL/GEOS imports are deliberately lazy so that the pure coordinate/radius
helpers remain usable (and testable) even on machines without the GDAL runtime;
every spatial *query* path still imports before running.
"""

# Max radius the public endpoint will accept (a city block to a small town).
MAX_RADIUS_M = 10_000
MIN_RADIUS_M = 100
DEFAULT_RADIUS_M = 2_000
DEFAULT_LIMIT = 20
MAX_LIMIT = 50

OPEN_STATUS_SUFFIX = ("resolved", "rejected")


class InvalidCoordinates(ValueError):
    pass


def make_point(lat: float, lon: float):
    """Build a 4326 Point, validating ranges as civic endpoints do."""
    lat = float(lat)
    lon = float(lon)
    if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lon <= 180.0):
        raise InvalidCoordinates("lat/lon outside valid ranges.")
    from django.contrib.gis.geos import GEOSGeometry

    return GEOSGeometry(f"POINT({lon} {lat})", srid=4326)


def clamp_radius(radius_m: float) -> float:
    return max(MIN_RADIUS_M, min(float(radius_m), MAX_RADIUS_M))


def upsert_location(issue, **kwargs):  # noqa: ANN001  (Django signal signature)
    """Create/refresh the spatial row for ``issue`` (post_save receiver)."""
    from .models import SpatialLocation

    try:
        point = make_point(issue.latitude, issue.longitude)
    except (InvalidCoordinates, TypeError, ValueError):
        return
    SpatialLocation.objects.update_or_create(
        issue=issue,
        defaults={"point": point},
    )


def nearby_issues(lat: float, lon: float, radius_m: float, limit: int):
    """Real PostGIS ``ST_DWithin`` search against open issues.

    Returns a list of dicts ``{distance_m, issue}`` ordered by distance. Only
    open issues (not resolved/rejected) match, mirroring the hotspots rule.
    """
    from django.contrib.gis.db.models.functions import Distance
    from django.contrib.gis.measure import D

    from .models import SpatialLocation

    point = make_point(lat, lon)
    radius_m = clamp_radius(radius_m)
    limit = max(1, min(int(limit or DEFAULT_LIMIT), MAX_LIMIT))

    rows = (
        SpatialLocation.objects.filter(
            point__distance_lte=(point, D(m=radius_m)),
        )
        .select_related("issue__duplicate_of")
        .annotate(distance_m=Distance("point", point))
        .exclude(issue__status__in=OPEN_STATUS_SUFFIX)
        .order_by("distance_m")[:limit]
    )
    return [
        {
            "distance_m": round(float(row.distance_m.m), 1)
            if row.distance_m is not None else 0.0,
            "issue": row.issue,
        }
        for row in rows
    ]