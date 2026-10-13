"""Describe the ACTIVE spatial path honestly.

The authority console reads this from ``GET /authority/meta/`` and from the
hotspots envelope so the map can label the aggregation method and whether a
real PostGIS spatial index serves this deployment — never implying a learned
anomaly model that has not been built.
"""

from __future__ import annotations

from django.conf import settings

# Default grid-cell size (degrees, ~220 m at topic latitudes).
HOTSPOT_CELL_DEGREES = 0.002


def describe_spatial_backend() -> dict:
    """Report which spatial machinery is genuinely switched on here.

    ``backend`` is ``postgis`` only when the DB is Postgres AND the geospat
    app is enabled; otherwise it is the pure-Python haversine/grid path. The
    hotspot cells returned by both paths come from the same fixed-grid
    aggregation over real issue coordinates.
    """
    postgis = getattr(settings, "POSTGRES_GIS_ENABLED", False)
    index_label = "postgis-gist" if postgis else "none"
    note = (
        "Hotspot cells are counted into fixed geographic grid bins from the "
        "issue coordinates the mobile app actually reported. This is an "
        "aggregation over real rows, not a learned anomaly model."
    )
    if postgis:
        note += " A PostGIS GiST spatial index serves the nearby-search path."
    else:
        note += (
            " This deployment runs the pure-Python haversine/grid path — "
            "there is no spatial index and none is claimed."
        )
    return {
        "backend": "postgis" if postgis else "haversine",
        "engine": "grid_aggregation",
        "distance_function": "grid_bins",
        "spatial_index": index_label,
        "note": note,
        "hotspot_cell_degrees": HOTSPOT_CELL_DEGREES,
    }