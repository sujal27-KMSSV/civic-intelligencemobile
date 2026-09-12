from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from .models import Issue

User = get_user_model()

# 1x1 transparent PNG (same bytes the Flutter test suite uses).
TINY_PNG = bytes(
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