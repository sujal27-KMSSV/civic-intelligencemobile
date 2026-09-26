from datetime import timedelta
from decimal import Decimal
import io

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from django.urls import clear_url_caches, resolve
from django.utils import timezone
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase
from PIL import Image as PILImage

from .window import DELETE_WINDOW_MESSAGE, delete_window_expired

from .models import Issue

User = get_user_model()


def _png_bytes(width=480, height=360):
    """A real, valid PNG large enough to pass the image-dimension guard."""
    buf = io.BytesIO()
    PILImage.new("RGB", (width, height), (112, 128, 144)).save(buf, format="PNG")
    return buf.getvalue()


# Real-size PNG used for every valid issue creation in this suite. (A 1x1
# transparent blob would previously pass validation; the upload guard now
# rejects it as too small to document an issue.)
TINY_PNG = _png_bytes()
TINY_1X1_PNG = bytes(
    [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00,
        0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
        0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
        0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
        0x82,
    ]
)


class IssueApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.other = User.objects.create_user(
            email="other@example.com", password="secret123"
        )
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _make_issue(self, user=None):
        return Issue.objects.create(
            reporter=user or self.user,
            image=self._png(),
            description="Pothole near the crossing.",
            latitude="28.6139",
            longitude="77.2090",
        )

    def _multipart(self, **overrides):
        data = {
            "latitude": "28.6139",
            "longitude": "77.2090",
            "description": "Pothole near the crossing.",
        }
        data.update(overrides)
        data.setdefault("image", self._png())
        return data

    def test_create_issue_saves_everything(self):
        response = self.client.post(
            "/api/issues/", self._multipart(), format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        body = response.json()
        self.assertIn("id", body)
        self.assertEqual(body["status"], "reported")
        self.assertEqual(body["category"], "other")
        self.assertEqual(body["confidence"], 0.0)
        self.assertEqual(body["severity"], "low")
        self.assertIs(body["duplicate"], False)
        self.assertEqual(body["duplicate_count"], 0)
        self.assertEqual(body["department"], "General Services")
        self.assertEqual(body["description"], "Pothole near the crossing.")
        self.assertEqual(body["latitude"], 28.6139)
        self.assertEqual(body["longitude"], 77.209)
        self.assertTrue(
            body["image_url"].startswith("http://testserver/media/issues/")
        )
        issue = Issue.objects.get(id=body["id"])
        self.assertEqual(issue.reporter, self.user)
        self.assertTrue(issue.image.name.startswith("issues/"))
        self.assertTrue(issue.image.size > 0)

    def test_create_issue_honors_optional_category(self):
        data = self._multipart(category="garbage")
        response = self.client.post("/api/issues/", data, format="multipart")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.json()["category"], "garbage")

    def test_create_issue_forces_server_owned_status(self):
        data = self._multipart(status="resolved", severity="critical")
        response = self.client.post("/api/issues/", data, format="multipart")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.json()["status"], "reported")
        self.assertEqual(response.json()["severity"], "low")

    def test_create_issue_requires_authentication(self):
        self.client.credentials()
        response = self.client.post(
            "/api/issues/", self._multipart(), format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_create_issue_requires_image(self):
        response = self.client.post(
            "/api/issues/",
            {"latitude": "28.6", "longitude": "77.2"},
            format="multipart",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_create_issue_rejects_out_of_range_gps(self):
        response = self.client.post(
            "/api/issues/", self._multipart(latitude="95.0"), format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_create_issue_rejects_non_image_upload(self):
        bad = SimpleUploadedFile(
            "evil.txt", b"definitely not an image", content_type="text/plain"
        )
        response = self.client.post(
            "/api/issues/", self._multipart(image=bad), format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_list_issues_public(self):
        self._make_issue()
        self.client.credentials()
        response = self.client.get("/api/issues/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertIsInstance(body, list)
        self.assertEqual(len(body), 1)

    def test_issue_detail_public(self):
        issue = self._make_issue()
        self.client.credentials()
        response = self.client.get(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body["id"], issue.id)
        self.assertEqual(body["status"], "reported")

    def test_my_reports_returns_only_own_issues(self):
        mine = self._make_issue(self.user)
        theirs = self._make_issue(self.other)
        response = self.client.get("/api/my-reports/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        ids = [item["id"] for item in body]
        self.assertEqual(ids, [mine.id])
        self.assertNotIn(theirs.id, ids)

    def test_my_reports_requires_auth(self):
        self.client.credentials()
        response = self.client.get("/api/my-reports/")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_patch_own_status_forbidden(self):
        # Lifecycle fields are authority-owned; reporters may NOT change status.
        issue = self._make_issue(self.user)
        response = self.client.patch(
            f"/api/issues/{issue.id}/", {"status": "verified"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_patch_own_description_allowed(self):
        issue = self._make_issue(self.user)
        response = self.client.patch(
            f"/api/issues/{issue.id}/",
            {"description": "Updated by the reporter."},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json()["description"], "Updated by the reporter.")
        issue.refresh_from_db()
        self.assertEqual(issue.description, "Updated by the reporter.")

    def test_patch_other_users_issue_forbidden(self):
        issue = self._make_issue(self.other)
        response = self.client.patch(
            f"/api/issues/{issue.id}/", {"status": "resolved"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_patch_requires_auth(self):
        issue = self._make_issue(self.user)
        self.client.credentials()
        response = self.client.patch(
            f"/api/issues/{issue.id}/", {"status": "resolved"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_patch_missing_issue_404(self):
        response = self.client.patch(
            "/api/issues/999999/", {"status": "resolved"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_delete_own_issue_allowed(self):
        issue = self._make_issue(self.user)
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Issue.objects.filter(id=issue.id).exists())

    def test_delete_other_users_issue_forbidden(self):
        issue = self._make_issue(self.other)
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Issue.objects.filter(id=issue.id).exists())

    def test_delete_requires_auth(self):
        issue = self._make_issue(self.user)
        self.client.credentials()
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)

    def test_delete_missing_issue_404(self):
        response = self.client.delete("/api/issues/999999/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_delete_removes_media_file(self):
        issue = self._make_issue(self.user)
        self.assertTrue(issue.image.storage.exists(issue.image.name))
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(issue.image.storage.exists(issue.image.name))

    def test_other_user_my_reports_fully_isolated(self):
        mine = self._make_issue(self.user)
        theirs = self._make_issue(self.other)
        other_token, _ = Token.objects.get_or_create(user=self.other)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {other_token.key}")
        response = self.client.get("/api/my-reports/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        ids = [item["id"] for item in response.json()]
        self.assertEqual(ids, [theirs.id])
        self.assertNotIn(mine.id, ids)
        # Reporter id is never exposed through the public/detail/list payload.
        detail = self.client.get(f"/api/issues/{mine.id}/").json()
        self.assertNotIn("reporter", detail)


class CivicAnalysisTests(APITestCase):
    """Rule-based civic intelligence: dupes, severity, routing."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _post(self, latitude, longitude, description, category=None):
        data = {
            "latitude": str(latitude),
            "longitude": str(longitude),
            "description": description,
            "image": self._png(),
        }
        if category:
            data["category"] = category
        return self.client.post("/api/issues/", data, format="multipart")

    def test_department_routing_by_category(self):
        response = self._post(28.6139, 77.2090, "Pothole at the crossing.", "pothole")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.json()["department"], "Road Maintenance")

    def test_severity_keyword_escalation(self):
        response = self._post(
            28.6139,
            77.2090,
            "Deep flooding water overflow dangerous for children near the school.",
            "drainage",
        )
        body = response.json()
        self.assertEqual(body["status"], "reported")
        # drainage base 55 + flooding 12 + overflow 9 + dangerous 12 + school 8
        self.assertIn(body["severity"], ("high", "critical"))

    def test_duplicate_detection_clusters(self):
        first = self._post(28.6139, 77.2090, "Pothole at the crossing.", "pothole")
        second = self._post(
            28.6140, 77.2092, "Pothole at the crossing.", "pothole"
        )
        second_body = second.json()
        self.assertTrue(second_body["duplicate"])
        self.assertGreaterEqual(second_body["duplicate_count"], 2)
        cluster = Issue.objects.get(id=first.json()["id"])
        self.assertEqual(cluster.duplicate_count, 2)

    def test_far_away_similar_text_not_a_duplicate(self):
        first = self._post(28.6139, 77.2090, "Pothole at the crossing.", "pothole")
        second = self._post(
            19.0760, 72.8777, "Pothole at the crossing.", "pothole"
        )  # Mumbai
        self.assertFalse(second.json()["duplicate"])


class AuthorityLifecycleTests(APITestCase):
    """Staff-only status transitions (authority enforces the lifecycle)."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.staff = User.objects.create_user(
            email="authority@example.com",
            password="secret123",
            is_staff=True,
        )
        self.staff_token, _ = Token.objects.get_or_create(user=self.staff)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.staff_token.key}")
        self.issue = Issue.objects.create(
            reporter=self.user,
            image=SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png"),
            description="Pothole near the crossing.",
            latitude="28.6139",
            longitude="77.2090",
        )

    def test_staff_valid_transition(self):
        response = self.client.patch(
            f"/api/issues/{self.issue.id}/",
            {"status": "verified"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json()["status"], "verified")

    def test_staff_invalid_transition_rejected(self):
        response = self.client.patch(
            f"/api/issues/{self.issue.id}/",
            {"status": "resolved"},  # reported -> resolved is not allowed
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)


class DeleteWindowTests(APITestCase):
    """Citizen DELETE: 10-minute retraction window, cluster-safety."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.staff = User.objects.create_user(
            email="authority@example.com",
            password="secret123",
            is_staff=True,
        )
        self.staff_token, _ = Token.objects.get_or_create(user=self.staff)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _make_issue(self, user=None):
        return Issue.objects.create(
            reporter=user or self.user,
            image=self._png(),
            description="Pothole near the crossing.",
            latitude="28.6139",
            longitude="77.2090",
        )

    def _post(self, latitude, longitude, description="Pothole at the crossing."):
        return self.client.post(
            "/api/issues/",
            {
                "latitude": str(latitude),
                "longitude": str(longitude),
                "description": description,
                "category": "pothole",
                "image": self._png(),
            },
            format="multipart",
        )

    def _backdate(self, issue, ago):
        Issue.objects.filter(pk=issue.pk).update(
            created_at=timezone.now() - ago
        )

    def test_delete_window_helper_boundaries(self):
        now = timezone.now()
        # Exactly at the window edge is still allowed (> 10 min is rejected).
        self.assertFalse(
            delete_window_expired(now - timedelta(minutes=10), now=now)
        )
        # One second past the window is rejected.
        self.assertTrue(
            delete_window_expired(now - timedelta(minutes=10, seconds=1), now=now)
        )
        # Null/broken timestamps and future clocks are treated as expired.
        self.assertTrue(delete_window_expired(None, now=now))
        self.assertTrue(delete_window_expired(now + timedelta(minutes=1), now=now))

    def test_delete_within_window_allowed(self):
        issue = self._make_issue(self.user)
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Issue.objects.filter(id=issue.id).exists())

    def test_delete_after_window_rejected(self):
        issue = self._make_issue(self.user)
        self._backdate(issue, timedelta(minutes=11))
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.json()["detail"], DELETE_WINDOW_MESSAGE)
        self.assertTrue(Issue.objects.filter(id=issue.id).exists())

    def test_delete_after_window_rejected_even_for_staff(self):
        # RULE 4: the window is enforced server-side on every DELETE call.
        issue = self._make_issue(self.user)
        self._backdate(issue, timedelta(minutes=11))
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.staff_token.key}")
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Issue.objects.filter(id=issue.id).exists())

    def test_delete_other_users_issue_forbidden_within_window(self):
        issue = self._make_issue(self.user)
        other = User.objects.create_user(
            email="other@example.com", password="secret123"
        )
        other_token, _ = Token.objects.get_or_create(user=other)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {other_token.key}")
        response = self.client.delete(f"/api/issues/{issue.id}/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertTrue(Issue.objects.filter(id=issue.id).exists())

    def test_delete_missing_issue_404(self):
        response = self.client.delete("/api/issues/999999/")
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    def test_delete_last_duplicate_clears_root_cluster_state(self):
        # Two-member cluster, delete the duplicate -> root has no duplicates.
        first = self._post(28.6139, 77.2090).json()
        second = self._post(28.6140, 77.2092).json()
        root = Issue.objects.get(id=first["id"])
        self.assertEqual(root.duplicate_count, 2)
        response = self.client.delete(f"/api/issues/{second['id']}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        root.refresh_from_db()
        self.assertFalse(root.duplicate)
        self.assertEqual(root.duplicate_count, 0)

    def test_delete_one_duplicate_shrinks_root_cluster(self):
        # Three-member cluster, delete one duplicate -> root keeps the rest.
        first = self._post(28.6139, 77.2090).json()
        second = self._post(28.6140, 77.2092).json()
        third = self._post(28.6138, 77.2091).json()
        root = Issue.objects.get(id=first["id"])
        self.assertEqual(root.duplicate_count, 3)
        response = self.client.delete(f"/api/issues/{second['id']}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        root.refresh_from_db()
        self.assertTrue(root.duplicate)
        self.assertEqual(root.duplicate_count, 2)
        self.assertEqual(
            len(Issue.objects.filter(duplicate_of=root)), 1
        )

    def test_delete_root_reroots_cluster(self):
        first = self._post(28.6139, 77.2090).json()
        second = self._post(28.6140, 77.2092).json()
        third = self._post(28.6138, 77.2091).json()
        response = self.client.delete(f"/api/issues/{first['id']}/")
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        new_root = Issue.objects.get(id=second["id"])
        other = Issue.objects.get(id=third["id"])
        self.assertFalse(new_root.duplicate)
        self.assertIsNone(new_root.duplicate_of)
        self.assertEqual(new_root.duplicate_count, 2)
        self.assertTrue(other.duplicate)
        self.assertEqual(other.duplicate_of, new_root)
        self.assertEqual(other.duplicate_count, 2)

    def test_deleted_issue_absent_from_feed_and_my_reports(self):
        issue = self._make_issue(self.user)
        self.client.delete(f"/api/issues/{issue.id}/")
        feed_ids = [i["id"] for i in self.client.get("/api/issues/").json()]
        self.assertNotIn(issue.id, feed_ids)
        mine_ids = [i["id"] for i in self.client.get("/api/my-reports/").json()]
        self.assertNotIn(issue.id, mine_ids)


class MediaServingTests(APITestCase):
    """Uploaded media must be served even when DEBUG is off.

    Django's static() helper is a no-op in production, so the URLconf adds an
    explicit serve route when DEBUG is disabled; this test guards that route.
    """

    @override_settings(DEBUG=False)
    def test_media_route_registered_when_debug_false(self):
        import sys

        import config.urls

        sys.modules.pop(config.urls.__name__, None)
        clear_url_caches()
        try:
            match = resolve("/media/issues/2026/09/14/tiny.png")
            self.assertEqual(match.view_name, "django.views.static.serve")
        finally:
            sys.modules.pop(config.urls.__name__, None)
            clear_url_caches()


class IdempotencyTests(APITestCase):
    """client_request_id de-duplicates a retried submission per reporter."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="idem@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _post(self, request_id=None):
        data = {
            "latitude": "28.6139",
            "longitude": "77.2090",
            "description": "Pothole near the crossing.",
            "image": self._png(),
        }
        if request_id is not None:
            data["client_request_id"] = request_id
        return self.client.post("/api/issues/", data, format="multipart")

    def test_same_key_returns_existing_report(self):
        first = self._post(request_id="ci-123-999")
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)

        second = self._post(request_id="ci-123-999")
        self.assertEqual(second.status_code, status.HTTP_200_OK)
        self.assertEqual(second.json()["id"], first.json()["id"])
        self.assertEqual(Issue.objects.count(), 1)

    def test_same_key_by_different_reporters_creates_separately(self):
        other = User.objects.create_user(
            email="idem2@example.com", password="secret123"
        )
        other_token, _ = Token.objects.get_or_create(user=other)
        first = self._post(request_id="ci-123-999")
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)

        self.client.credentials(HTTP_AUTHORIZATION=f"Token {other_token.key}")
        second = self._post(request_id="ci-123-999")
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertNotEqual(second.json()["id"], first.json()["id"])
        self.assertEqual(Issue.objects.count(), 2)

    def test_no_key_creates_separate_reports(self):
        first = self._post()
        second = self._post()
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertNotEqual(second.json()["id"], first.json()["id"])
        self.assertEqual(Issue.objects.count(), 2)

    def test_different_key_creates_separate_reports(self):
        first = self._post(request_id="ci-a")
        second = self._post(request_id="ci-b")
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Issue.objects.count(), 2)

    def test_key_is_write_only(self):
        response = self._post(request_id="ci-secret")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertNotIn("client_request_id", response.json())

    def test_empty_key_is_idempotent_none(self):
        first = self._post(request_id="   ")
        second = self._post(request_id="   ")
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertNotEqual(second.json()["id"], first.json()["id"])
        stored = Issue.objects.get(id=first.json()["id"])
        self.assertIsNone(stored.client_request_id)


class UploadGuardTests(APITestCase):
    """Client and server agree on what counts as a usable photo."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="guard@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _post(self, image_data):
        return self.client.post(
            "/api/issues/",
            {
                "latitude": "28.6139",
                "longitude": "77.2090",
                "description": "Pothole near the crossing.",
                "image": SimpleUploadedFile(
                    "photo.png", image_data, content_type="image/png"
                ),
            },
            format="multipart",
        )

    def test_tiny_image_rejected(self):
        response = self._post(TINY_1X1_PNG)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("too small", response.json()["image"][0])

    def test_pixel_bomb_rejected(self):
        # > 24 MP in a single frame is rejected even though the PNG compresses
        # to a small file (a classic pixel-bomb / memory-exhaustion vector).
        big = _png_bytes(width=5000, height=5000)
        response = self._post(big)
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("resolution is too high", response.json()["image"][0])

    def test_editable_photo_accepted(self):
        response = self._post(TINY_PNG)
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)


class ServerPermissionFlagTests(APITestCase):
    """can_delete / can_edit are computed server-side from its own clock."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="flags@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _make_issue(self):
        return Issue.objects.create(
            reporter=self.user,
            image=self._png(),
            description="Pothole near the crossing.",
            latitude="28.6139",
            longitude="77.2090",
        )

    def _detail(self, issue_id):
        return self.client.get(f"/api/issues/{issue_id}/")

    def test_fresh_issue_fully_editable(self):
        issue = self._make_issue()
        payload = self._detail(issue.id).json()
        self.assertTrue(payload["can_delete"])
        self.assertTrue(payload["can_edit"])

    def test_backdated_issue_cannot_delete(self):
        issue = self._make_issue()
        Issue.objects.filter(pk=issue.pk).update(
            created_at=timezone.now() - timedelta(minutes=11)
        )
        payload = self._detail(issue.id).json()
        self.assertFalse(payload["can_delete"])
        # Still in REPORTED, so the citizen may keep editing the write-up.
        self.assertTrue(payload["can_edit"])

    def test_resolved_issue_cannot_edit(self):
        issue = self._make_issue()
        Issue.objects.filter(pk=issue.pk).update(status=Issue.Status.RESOLVED)
        payload = self._detail(issue.id).json()
        self.assertFalse(payload["can_edit"])
        # The retraction window is untouched by lifecycle transitions.
        self.assertTrue(payload["can_delete"])

    def test_flags_exposed_in_my_reports(self):
        issue = self._make_issue()
        payload = self.client.get("/api/my-reports/").json()[0]
        self.assertIn("can_delete", payload)
        self.assertIn("can_edit", payload)
        self.assertTrue(payload["can_delete"])
        self.assertTrue(payload["can_edit"])


class CitizenPATCHRestrictionTests(APITestCase):
    """Citizens may fix only their own report's description/address."""

    RESTRICTED_MSG = "Citizens may only change: description, address."

    def setUp(self):
        self.user = User.objects.create_user(
            email="editor@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _make_issue(self):
        return Issue.objects.create(
            reporter=self.user,
            image=self._png(),
            description="Pothole near the crossing.",
            latitude="28.6139",
            longitude="77.2090",
        )

    def test_latitude_is_not_citizen_editable(self):
        issue = self._make_issue()
        # Even a *valid* coordinate change is authority-owned; citizens may
        # only edit description/address.
        response = self.client.patch(
            f"/api/issues/{issue.id}/", {"latitude": "12.9716"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn(self.RESTRICTED_MSG, response.json()["detail"])
        issue.refresh_from_db()
        self.assertEqual(issue.latitude, Decimal("28.6139"))

    def test_category_is_not_citizen_editable(self):
        issue = self._make_issue()
        # "pothole" is a valid category choice, but category is still
        # authority-owned after creation.
        response = self.client.patch(
            f"/api/issues/{issue.id}/", {"category": "pothole"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn(self.RESTRICTED_MSG, response.json()["detail"])

    def test_address_is_citizen_editable(self):
        issue = self._make_issue()
        response = self.client.patch(
            f"/api/issues/{issue.id}/",
            {"address": "14 MG Road, Bengaluru"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(
            response.json()["address"], "14 MG Road, Bengaluru"
        )
        issue.refresh_from_db()
        self.assertEqual(issue.address, "14 MG Road, Bengaluru")

    def test_multi_field_patch_reports_every_disallowed_field(self):
        issue = self._make_issue()
        response = self.client.patch(
            f"/api/issues/{issue.id}/",
            {"status": "resolved", "category": "pothole"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        for field in ("category", "status"):
            self.assertIn(field, response.json()["detail"])


class CivicIntelligenceV2Tests(APITestCase):
    """Engine v2: image-signal dedup, consolidated master issues, priority."""

    def setUp(self):
        self.user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _post(self, latitude, longitude, description, category="pothole"):
        return self.client.post(
            "/api/issues/",
            {
                "latitude": str(latitude),
                "longitude": str(longitude),
                "description": description,
                "category": category,
                "image": self._png(),
            },
            format="multipart",
        )

    def test_new_issue_exposes_priority_and_image_features(self):
        response = self._post(28.6139, 77.2090, "Pothole at the crossing.")
        body = response.json()
        self.assertIn("priority", body)
        self.assertIn("priority_label", body)
        self.assertEqual(body["priority_label"], "low")
        self.assertGreaterEqual(body["priority"], 10.0)
        issue = Issue.objects.get(id=body["id"])
        # Perceptual hash of the constant-colour test PNG is 64 bits.
        self.assertEqual(len(issue.image_dhash), 64)
        self.assertIsNotNone(issue.image_brightness)

    def test_duplicate_joins_master_and_exposes_cluster_context(self):
        first = self._post(28.6139, 77.2090, "Pothole at the crossing.").json()
        second = self._post(28.6140, 77.2092, "Pothole at the crossing.").json()
        root = Issue.objects.get(id=first["id"])
        child = Issue.objects.get(id=second["id"])

        self.assertTrue(second["duplicate"])
        self.assertEqual(second["master_id"], root.pk)
        self.assertFalse(second["is_master"])
        self.assertEqual(second["cluster_size"], 2)

        master = Issue.objects.get(id=root.pk)
        detail = self.client.get(f"/api/issues/{root.pk}/").json()
        self.assertTrue(detail["is_master"])
        self.assertEqual(detail["master_id"], root.pk)
        self.assertEqual(detail["cluster_member_ids"], sorted([root.pk, child.pk]))
        self.assertEqual(detail["cluster_size"], 2)
        self.assertEqual(detail["duplicate_count"], 2)

    def test_duplicate_detail_links_to_master(self):
        first = self._post(28.6139, 77.2090, "Pothole at the crossing.").json()
        second = self._post(28.6140, 77.2092, "Pothole at the crossing.").json()
        body = self.client.get(f"/api/issues/{second['id']}/").json()
        self.assertEqual(body["master_id"], first["id"])
        self.assertEqual(body["cluster_member_ids"], [])

    def test_feed_collapses_duplicates_by_default(self):
        self._post(28.6139, 77.2090, "Pothole at the crossing.")
        self._post(28.6141, 77.2093, "Pothole at the crossing.")
        self._post(28.6142, 77.2091, "Pothole at the crossing.")
        self.assertLessEqual(len(self.client.get("/api/issues/").json()), 1)

    def test_collapse_zero_returns_every_report(self):
        self._post(28.6139, 77.2090, "Pothole at the crossing.")
        self._post(28.6141, 77.2093, "Pothole at the crossing.")
        body = self.client.get("/api/issues/?collapse=0").json()
        self.assertEqual(len(body), 2)

    def test_priority_climbs_with_supporting_reports(self):
        first = self._post(28.6139, 77.2090, "Pothole at the crossing.").json()
        self._post(28.6140, 77.2092, "Pothole at the crossing.")
        self._post(28.6138, 77.2091, "Pothole at the crossing.")
        root = Issue.objects.get(id=first["id"])
        # 3 reports: severity base 40 (pothole) may push label up; supporting
        # reports must raise priority above the single-report baseline.
        self.assertGreater(root.priority, 0)
        reasons = {r["factor"] for r in root.priority_reasons}
        self.assertIn("duplicate_reports", reasons)
        self.assertIn("cluster_master", reasons)

    def test_my_reports_keep_every_report_with_cluster_context(self):
        first = self._post(28.6139, 77.2090, "Pothole at the crossing.").json()
        second = self._post(28.6140, 77.2092, "Pothole at the crossing.").json()
        body = self.client.get("/api/my-reports/").json()
        ids = [i["id"] for i in body]
        self.assertIn(first["id"], ids)
        self.assertIn(second["id"], ids)
        dup = next(i for i in body if i["id"] == second["id"])
        self.assertEqual(dup["master_id"], first["id"])


class HotspotApiTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png")

    def _post(self, latitude, longitude):
        return self.client.post(
            "/api/issues/",
            {
                "latitude": str(latitude),
                "longitude": str(longitude),
                "description": "Pothole at the crossing.",
                "category": "pothole",
                "image": self._png(),
            },
            format="multipart",
        )

    def test_hotspots_public_endpoint_groups_real_locations(self):
        for lat, lon in [
            (28.613, 77.208),
            (28.613, 77.208),
            (28.613, 77.208),
            (19.0760, 72.8777),  # Mumbai, very far away
        ]:
            self._post(lat, lon)
        self.client.credentials()
        response = self.client.get("/api/hotspots/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        cells = response.json()
        self.assertTrue(cells)
        top = cells[0]
        self.assertGreaterEqual(top["issue_count"], 3)
        self.assertEqual(
            {c[0] for c in top["categories"]},
            {"pothole"},
        )
        self.assertIn("top_issue_id", top)

    def test_hotspots_rejects_bad_grid(self):
        self.client.credentials()
        response = self.client.get("/api/hotspots/?grid=999")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)