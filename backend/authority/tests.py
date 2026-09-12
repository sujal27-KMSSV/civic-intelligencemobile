"""Tests for the authority dashboard + staff API."""

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.urls import reverse
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

from issues.models import Issue

from . import service

User = get_user_model()

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


def make_issue(reporter, **kwargs):
    data = dict(
        reporter=reporter,
        image=SimpleUploadedFile("photo.png", TINY_PNG, content_type="image/png"),
        description="Pothole near the crossing.",
        latitude="28.6139",
        longitude="77.2090",
    )
    data.update(kwargs)
    return Issue.objects.create(**data)


class AuthorityApiTests(APITestCase):
    def setUp(self):
        self.citizen = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.staff = User.objects.create_user(
            email="authority@example.com",
            password="secret123",
            is_staff=True,
        )
        self.staff_token, _ = Token.objects.get_or_create(user=self.staff)

    def _auth(self):
        self.client.credentials(
            HTTP_AUTHORIZATION=f"Token {self.staff_token.key}"
        )

    def test_non_staff_cannot_access_api(self):
        token, _ = Token.objects.get_or_create(user=self.citizen)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        response = self.client.get("/api/authority/stats/")
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_stats(self):
        self._auth()
        make_issue(self.citizen)
        response = self.client.get("/api/authority/stats/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body["total"], 1)
        self.assertEqual(body["open"], 1)
        self.assertIn("by_status", body)

    def test_issue_list_hides_resolved_by_default(self):
        self._auth()
        open_issue = make_issue(self.citizen)
        resolved = make_issue(
            self.citizen, status=Issue.Status.RESOLVED
        )
        response = self.client.get("/api/authority/issues/")
        ids = [item["id"] for item in response.json()]
        self.assertIn(open_issue.id, ids)
        self.assertNotIn(resolved.id, ids)

    def test_transition_and_resolve_flow(self):
        self._auth()
        issue = make_issue(self.citizen)
        transit = self.client.post(
            reverse("authority_api:transition", args=[issue.id]),
            {"new_status": "verified"},
            format="json",
        )
        self.assertEqual(transit.status_code, status.HTTP_200_OK)
        self.assertEqual(transit.json()["status"], "verified")
        issue.refresh_from_db()
        self.assertEqual(issue.status, "verified")

    def test_cannot_skip_to_resolved_without_evidence(self):
        self._auth()
        issue = make_issue(self.citizen)
        transit = self.client.post(
            reverse("authority_api:transition", args=[issue.id]),
            {"new_status": "resolved"},
            format="json",
        )
        self.assertEqual(transit.status_code, status.HTTP_400_BAD_REQUEST)

    def test_resolve_with_evidence(self):
        self._auth()
        issue = make_issue(self.citizen, status=Issue.Status.IN_PROGRESS)
        response = self.client.post(
            reverse("authority_api:resolve", args=[issue.id]),
            {
                "image": SimpleUploadedFile(
                    "after.png", TINY_PNG, content_type="image/png"
                ),
                "notes": "Repaved by the crew.",
            },
            format="multipart",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        issue.refresh_from_db()
        self.assertEqual(issue.status, "resolved")
        self.assertTrue(issue.resolution_image.name.startswith("resolution/"))
        self.assertEqual(issue.resolution_notes, "Repaved by the crew.")
        self.assertIsNotNone(issue.resolved_at)


class AuthorityServiceTests(APITestCase):
    def test_invalid_transition_rejected(self):
        issue = make_issue(self.citizen())
        issue, error = service.transition_issue(issue, "resolved")
        self.assertIsNotNone(error)

    def test_reopen_clears_resolved_at(self):
        from django.utils import timezone

        issue = make_issue(self.citizen())
        issue.status = Issue.Status.RESOLVED
        issue.resolved_at = timezone.now()
        issue.save()
        issue, error = service.transition_issue(issue, "in_progress")
        self.assertIsNone(error)
        self.assertEqual(issue.status, "in_progress")
        self.assertIsNone(issue.resolved_at)

    @staticmethod
    def citizen():
        return User.objects.create_user(
            email="c2@example.com", password="secret123"
        )