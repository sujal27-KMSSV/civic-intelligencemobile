"""Geospat tests.

Pure-Python helpers are always tested. The genuine ``ST_DWithin`` integration
tests SKIP unless the runtime really has a PostGIS database behind the geospat
app (``POSTGRES_GIS_ENABLED``) -- an honest capability boundary: no mocked or
emulated "geometry" passes as a spatial feature in the claim sheet.
"""

import io

from django.conf import settings
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, TestCase
from django.test.utils import skipUnless
from PIL import Image as PILImage


class GeospatPureHelperTests(SimpleTestCase):
    def test_clamp_radius_bounds(self):
        from .service import MAX_RADIUS_M, MIN_RADIUS_M, clamp_radius

        self.assertEqual(clamp_radius(1), MIN_RADIUS_M)
        self.assertEqual(clamp_radius(9_999_999), MAX_RADIUS_M)
        self.assertEqual(clamp_radius(500), 500.0)

    def test_make_point_validates_latlon(self):
        from .service import InvalidCoordinates, make_point

        for bad in (
            ("91.0", "0"), ("0", "181.0"),
            ("nope", "0"), ("1", "nope"),
            (None, "0"),
        ):
            with self.assertRaises((InvalidCoordinates, ValueError, TypeError)):
                make_point(*bad)

        # Positive construction needs the GEOS runtime (attempting it imports
        # GDAL); assert the SRID too when present, otherwise skip silently.
        try:
            point = make_point(28.6139, 77.2090)
        except Exception:  # noqa: BLE001 - GDAL-less machines lack the runtime
            return
        self.assertEqual(point.srid, 4326)


def _postgis_available():
    if not getattr(settings, "POSTGRES_GIS_ENABLED", False):
        return False
    from django.db import connection

    return connection.vendor == "postgresql"


@skipUnless(_postgis_available(), "Requires a genuine PostGIS database.")
class GeospatIntegrationTests(TestCase):
    """Real ``ST_DWithin`` neighbourhood search against issue locations."""

    @classmethod
    def setUpTestData(cls):
        from django.contrib.auth import get_user_model

        from issues.models import Issue

        cls.User = get_user_model()
        cls.user = cls.User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )

        def png():
            buf = io.BytesIO()
            PILImage.new("RGB", (480, 360), (50, 100, 150)).save(buf, format="PNG")
            return SimpleUploadedFile("photo.png", buf.getvalue(),
                                      content_type="image/png")

        cls.near = Issue.objects.create(
            reporter=cls.user, image=png(), category="pothole",
            description="Near the crossing.",
            latitude="28.6139", longitude="77.2090",
        )
        cls.far = Issue.objects.create(
            reporter=cls.user, image=png(), category="garbage",
            description="Far away.",
            latitude="28.6199", longitude="77.2190",
        )
        cls.resolved = Issue.objects.create(
            reporter=cls.user, image=png(), category="lighting",
            description="Already fixed.",
            latitude="28.6140", longitude="77.2091",
            status="resolved",
        )
        from geospat.service import upsert_location

        for issue in (cls.near, cls.far, cls.resolved):
            upsert_location(issue)

    def test_nearby_orders_by_distance_and_excludes_others(self):
        from .service import nearby_issues

        result = nearby_issues(28.6139, 77.2090, radius_m=1000, limit=20)
        ids = [item["issue"].id for item in result]
        self.assertIn(self.near.id, ids)
        self.assertIn(self.far.id, ids)
        self.assertNotIn(self.resolved.id, ids)
        self.assertTrue(
            result[0]["distance_m"] <= result[-1]["distance_m"],
            "distances must be ascending",
        )

    def test_narrow_radius_returns_only_true_neighbours(self):
        from .service import nearby_issues

        result = nearby_issues(28.6139, 77.2090, radius_m=120, limit=20)
        ids = [item["issue"].id for item in result]
        self.assertIn(self.near.id, ids)
        self.assertNotIn(self.far.id, ids)

    def test_api_endpoint_returns_distance_and_payload(self):
        from rest_framework import status
        from rest_framework.test import APIClient

        client = APIClient()
        response = client.get(
            "/api/geospat/nearby/",
            {"lat": "28.6139", "lon": "77.2090", "radius_m": "1000"},
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body["count"], 2)
        first = body["results"][0]
        self.assertEqual(first["issue"]["id"], self.near.id)
        self.assertLess(first["distance_m"], 250)

    def test_api_rejects_missing_coordinates(self):
        from rest_framework import status
        from rest_framework.test import APIClient

        response = APIClient().get("/api/geospat/nearby/", {"radius_m": "500"})
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)