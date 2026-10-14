"""Tests for the authority dashboard + staff API."""

import os
from unittest import mock

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
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

    def test_meta(self):
        self._auth()
        response = self.client.get("/api/authority/meta/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(
            body["ordering"],
            ["priority", "newest", "oldest", "cluster", "severity", "reports", "status"],
        )
        self.assertEqual(body["scopes"], ["masters", "supporting", "all"])
        self.assertIn("Unassigned", body["departments"]["assignable"])
        self.assertEqual(
            body["departments"]["by_category"]["pothole"], "Road Maintenance"
        )
        self.assertIn("valid_transitions", body["lifecycle"])
        caps = body["capabilities"]
        self.assertEqual(caps["spatial"]["engine"], "grid_aggregation")
        self.assertIn("engine", caps["priority_engine"])
        self.assertIn("components", caps["priority_engine"])
        self.assertIn("engine_honest_label", caps["priority_engine"])
        self.assertEqual(caps["spatial"]["spatial_index"], "none")

    def test_meta_lists_officers(self):
        self._auth()
        response = self.client.get("/api/authority/meta/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body["officer_count"], 1)

    def test_list_rejects_unknown_ordering_with_valid_keys(self):
        self._auth()
        response = self.client.get("/api/authority/issues/?ordering=bogus")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        body = response.json()
        self.assertIn("bogus", body["detail"])
        for key in ["priority", "newest", "oldest", "cluster", "severity", "reports", "status"]:
            self.assertIn(key, body["detail"])

    def test_list_rejects_unknown_filter_values(self):
        self._auth()
        cases = [
            "/api/authority/issues/?status=fake",
            "/api/authority/issues/?severity=extreme",
            "/api/authority/issues/?category=alien",
            "/api/authority/issues/?priority_class=urgent",
            "/api/authority/issues/?assigned=maybe",
            "/api/authority/issues/?scope=none",
        ]
        for url in cases:
            response = self.client.get(url)
            self.assertEqual(
                response.status_code, status.HTTP_400_BAD_REQUEST, msg=url
            )

    def test_list_scope_defaults_to_masters(self):
        self._auth()
        root = make_issue(self.citizen)
        supporting = make_issue(self.citizen)
        supporting.duplicate_of = root
        supporting.save()
        self.assertIsNotNone(supporting.duplicate_of_id)
        response = self.client.get("/api/authority/issues/?scope=all")
        self.assertEqual(len(response.json()), 2)
        masters = self.client.get("/api/authority/issues/?scope=masters")
        self.assertEqual(len(masters.json()), 1)
        default = self.client.get("/api/authority/issues/")
        self.assertEqual(len(default.json()), 1)
        supporting_only = self.client.get("/api/authority/issues/?scope=supporting")
        self.assertEqual(len(supporting_only.json()), 1)
        self.assertEqual(supporting_only.json()[0]["id"], supporting.id)

    def test_list_pagination_envelope(self):
        self._auth()
        for _ in range(3):
            make_issue(self.citizen)
        response = self.client.get("/api/authority/issues/?page=1&page_size=2")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body["count"], 3)
        self.assertEqual(body["page"], 1)
        self.assertEqual(body["page_size"], 2)
        self.assertEqual(body["total_pages"], 2)
        self.assertEqual(len(body["results"]), 2)
        without_page = self.client.get("/api/authority/issues/")
        self.assertIsInstance(without_page.json(), list)

    def test_list_ordering_by_priority(self):
        self._auth()
        low = make_issue(self.citizen, priority=10, priority_label="low")
        high = make_issue(
            self.citizen, priority=70, priority_label="high"
        )
        response = self.client.get("/api/authority/issues/?ordering=priority")
        ids = [item["id"] for item in response.json()]
        self.assertEqual(ids, [high.id, low.id])

    def test_q_searches_description(self):
        self._auth()
        issue = make_issue(self.citizen)
        response = self.client.get(
            f"/api/authority/issues/?q={issue.description[:10]}"
        )
        ids = [item["id"] for item in response.json()]
        self.assertIn(issue.id, ids)

    def test_list_filters_by_department_and_assigned(self):
        self._auth()
        officer = User.objects.create_user(
            email="foreman@example.com", password="secret123", is_staff=True
        )
        road = make_issue(self.citizen, department="Road Maintenance")
        make_issue(
            self.citizen,
            department="Solid Waste Management",
            assigned_to_id=officer.id,
        )
        dept = self.client.get(
            "/api/authority/issues/?department=Road%20Maintenance"
        )
        self.assertEqual([i["id"] for i in dept.json()], [road.id])
        self.assertEqual(dept.json()[0]["department"], "Road Maintenance")
        assigned = self.client.get("/api/authority/issues/?assigned=assigned")
        self.assertEqual(len(assigned.json()), 1)
        self.assertEqual(assigned.json()[0]["assigned_to"], officer.id)
        unassigned = self.client.get("/api/authority/issues/?assigned=unassigned")
        self.assertEqual(len(unassigned.json()), 1)
        self.assertIsNone(unassigned.json()[0]["assigned_to"])

    def test_detail_returns_cluster_and_priority_explanation(self):
        self._auth()
        root = make_issue(
            self.citizen,
            priority=70,
            priority_label="high",
            duplicate_count=2,  # duplicate_count = total reports incl. the root
            priority_reasons=[
                {"factor": "severity", "points": 20, "note": "crack 30cm"},
                {"factor": "reported_recently", "points": 10, "note": "within 24h"},
            ],
            analysis={"engine": "rule-based-civic-analysis-v3"},
        )
        dup = make_issue(self.citizen, description="Same pothole, corner.")
        dup.duplicate_of = root
        dup.duplicate = True
        dup.confidence = 0.9
        dup.analysis = {
            "duplicate": {
                "evidence": [
                    {"name": "location", "value": 0.95},
                    {"name": "text", "value": 0.7},
                    {"name": "visual", "value": None},
                ],
                "similarity_score": 0.8,
                "root_id": root.id,
            }
        }
        dup.save()

        response = self.client.get(f"/api/authority/issues/{root.id}/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body["id"], root.id)
        self.assertEqual(body["master_id"], root.id)
        self.assertTrue(body["is_master"])
        self.assertEqual(body["cluster_size"], 2)
        self.assertEqual(set(body["cluster_member_ids"]), {root.id, dup.id})
        self.assertEqual({i["id"] for i in body["cluster"]}, {root.id, dup.id})
        self.assertEqual(body["master"]["id"], root.id)
        self.assertIn("allowed_transitions", body)
        self.assertNotIn("resolved", body["allowed_transitions"])

        explanation = body["priority_explanation"]
        self.assertEqual(explanation["class"], "high")
        self.assertEqual(explanation["engine"], "rule-based-civic-analysis-v3")
        self.assertEqual(
            sorted(r["code"] for r in explanation["reasons"]),
            ["reported_recently", "severity"],
        )
        self.assertEqual(explanation["components"]["severity"], 20)
        self.assertEqual(explanation["inputs"]["cluster_size"], 2)
        self.assertIsNone(explanation["inputs"]["mean_similarity"])

    def test_supporting_detail_reports_honest_duplicate_signals(self):
        self._auth()
        root = make_issue(self.citizen)
        dup = make_issue(self.citizen, description="Same pothole, corner.")
        dup.duplicate_of = root
        dup.duplicate = True
        dup.confidence = 0.9
        dup.analysis = {
            "duplicate": {
                "evidence": [
                    {"name": "location", "value": 0.95},
                    {"name": "text", "value": 0.7},
                    {"name": "visual", "value": None},
                ],
                "similarity_score": 0.8,
                "root_id": root.id,
            }
        }
        dup.save()
        response = self.client.get(f"/api/authority/issues/{dup.id}/")
        body = response.json()
        signals = body["duplicate_signals"]
        self.assertIsNotNone(signals)
        self.assertEqual(set(signals["signals"]), {"location", "text"})
        self.assertEqual(signals["similarity_score"], 0.8)
        used = signals["used_weights"]
        self.assertAlmostEqual(sum(used.values()), 1.0, places=4)
        self.assertIn("location", used)
        self.assertIn("text", used)
        self.assertNotIn("visual", used)

    def test_standalone_detail_has_no_duplicate_signals(self):
        self._auth()
        issue = make_issue(self.citizen)
        response = self.client.get(f"/api/authority/issues/{issue.id}/")
        body = response.json()
        self.assertIsNone(body["duplicate_signals"])
        self.assertEqual(body["cluster_size"], 1)
        self.assertFalse(body["is_master"])

    def test_patch_assignment(self):
        self._auth()
        issue = make_issue(self.citizen)
        officer = User.objects.create_user(
            email="officer@example.com",
            password="secret123",
            is_staff=True,
            first_name="Anita",
            last_name="Kaur",
        )
        response = self.client.patch(
            f"/api/authority/issues/{issue.id}/",
            {"department": "Road Maintenance", "officer_id": officer.id},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertEqual(body["department"], "Road Maintenance")
        self.assertEqual(body["assigned_to"], officer.id)
        self.assertEqual(body["assigned_to_email"], officer.email)
        self.assertEqual(body["assigned_to_name"], "Anita Kaur")
        self.assertIsNotNone(body["assigned_at"])
        issue.refresh_from_db()
        self.assertEqual(issue.assigned_to_id, officer.id)
        self.assertIsNotNone(issue.assigned_at)

    def test_patch_unassign(self):
        self._auth()
        officer = User.objects.create_user(
            email="officer@example.com",
            password="secret123",
            is_staff=True,
        )
        issue = make_issue(
            self.citizen, department="Road Maintenance", assigned_to=officer
        )
        response = self.client.patch(
            f"/api/authority/issues/{issue.id}/",
            {"officer_id": None, "department": "Public Lighting"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertIsNone(body["assigned_to"])
        self.assertIsNone(body["assigned_at"])
        self.assertEqual(body["department"], "Public Lighting")

    def test_patch_rejects_unknown_department_and_non_staff(self):
        self._auth()
        issue = make_issue(self.citizen)
        bad_dept = self.client.patch(
            f"/api/authority/issues/{issue.id}/",
            {"department": "mars"},
            format="json",
        )
        self.assertEqual(bad_dept.status_code, status.HTTP_400_BAD_REQUEST)
        bad_officer = self.client.patch(
            f"/api/authority/issues/{issue.id}/",
            {"officer_id": self.citizen.id},  # citizen, not staff
            format="json",
        )
        self.assertEqual(bad_officer.status_code, status.HTTP_400_BAD_REQUEST)

    def test_hotspots_envelope(self):
        self._auth()
        for _ in range(2):
            make_issue(self.citizen)
        response = self.client.get("/api/authority/hotspots/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        self.assertIn("hotspots", body)
        self.assertEqual(body["total_masters"], 2)
        self.assertEqual(body["method"], "grid_aggregation")
        self.assertIn("method_honest_label", body)
        self.assertEqual(body["spatial_backend"]["backend"], "haversine")
        self.assertEqual(body["limit"], 10)

    def test_hotspots_rejects_bad_grid(self):
        self._auth()
        response = self.client.get("/api/authority/hotspots/?grid=abc")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_stats(self):
        self._auth()
        make_issue(self.citizen)
        response = self.client.get("/api/authority/stats/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        body = response.json()
        # Console-shaped Stats payload (not the legacy template shape).
        self.assertEqual(body["active_issues"], 1)
        self.assertEqual(body["total_reports"], 1)
        self.assertEqual(body["total_masters"], 1)
        self.assertEqual(body["assigned_open"], 0)
        self.assertEqual(body["unassigned_open"], 1)
        self.assertIn("by_status", body)
        self.assertIn("by_severity", body)
        self.assertIn("active_department_names", body)
        self.assertIn("counting_convention", body)
        # Hotspot analytics are real aggregates, not a model.
        self.assertIn("analytics", body)
        self.assertIn("hotspot_cells", body["analytics"])
        self.assertIn("open_age_hours", body["analytics"])
        self.assertIn("trend_reports", body["analytics"])

    def test_stats_enum_buckets_are_keyed_by_raw_values(self):
        self._auth()
        make_issue(
            self.citizen,
            severity=Issue.Severity.HIGH,
            status=Issue.Status.IN_PROGRESS,
        )
        response = self.client.get("/api/authority/stats/")
        body = response.json()
        self.assertEqual(body["by_status"].get("in_progress"), 1)
        self.assertEqual(body["by_severity"].get("high"), 1)

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

    def test_resolve_records_honest_evaluation_in_analysis(self):
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
        resolution = (issue.analysis or {}).get("resolution")
        self.assertIsNotNone(resolution)
        self.assertEqual(resolution["method"], "dhash-hamming-64")
        self.assertIn("interpretation", resolution)
        self.assertIn("brightness_before", resolution)
        self.assertEqual(
            resolution["similarity"], issue.resolution_similarity,
        )
        self.assertIn("note", resolution)
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


class BootstrapAdminCommandTests(TestCase):
    def test_creates_staff_user_and_is_idempotent(self):
        from django.core.management import call_command
        from django.core.management.base import CommandError

        call_command(
            "bootstrap_admin",
            email="boss@example.com",
            password="Secret123!",
        )
        user = User.objects.get(email="boss@example.com")
        self.assertTrue(user.is_staff)
        self.assertFalse(user.is_superuser)
        self.assertTrue(user.check_password("Secret123!"))

        # Re-run: same user, password untouched.
        call_command(
            "bootstrap_admin",
            email="boss@example.com",
            password="Other456!",
        )
        user.refresh_from_db()
        self.assertTrue(user.is_staff)
        self.assertTrue(user.check_password("Secret123!"))

    def test_promotes_existing_citizen_without_touching_password(self):
        from django.core.management import call_command

        citizen = User.objects.create_user(
            email="promote@example.com", password="oldpass", is_staff=False
        )
        call_command(
            "bootstrap_admin",
            email="promote@example.com",
            password="NewPass9!",
        )
        citizen.refresh_from_db()
        self.assertTrue(citizen.is_staff)
        # Promotion never resets an existing account's password.
        self.assertTrue(citizen.check_password("oldpass"))
        self.assertFalse(citizen.check_password("NewPass9!"))

    def test_superuser_flag(self):
        from django.core.management import call_command

        call_command(
            "bootstrap_admin",
            email="root@example.com",
            password="RootPass9!",
            superuser=True,
        )
        user = User.objects.get(email="root@example.com")
        self.assertTrue(user.is_staff)
        self.assertTrue(user.is_superuser)

    def test_requires_email(self):
        from django.core.management import call_command
        from django.core.management.base import CommandError

        with self.assertRaises(CommandError):
            call_command("bootstrap_admin")

    def test_unattended_requires_strong_secret(self):
        from django.core.management import call_command
        from django.core.management.base import CommandError

        # Missing secret.
        with self.assertRaises(CommandError):
            call_command(
                "bootstrap_admin",
                email="a@example.com",
                unattended=True,
            )
        # Too-short secret.
        with mock.patch.dict(
            os.environ,
            {"CIVIC_BOOTSTRAP_SECRET": "tooshort"},
        ):
            with self.assertRaises(CommandError):
                call_command(
                    "bootstrap_admin",
                    email="a@example.com",
                    unattended=True,
                )
        self.assertFalse(User.objects.filter(email="a@example.com").exists())

    def test_unattended_requires_password_env(self):
        from django.core.management import call_command
        from django.core.management.base import CommandError

        with mock.patch.dict(
            os.environ,
            {"CIVIC_BOOTSTRAP_SECRET": "s" * 40},
        ):
            with self.assertRaises(CommandError):
                call_command(
                    "bootstrap_admin",
                    email="a@example.com",
                    unattended=True,
                )
        self.assertFalse(User.objects.filter(email="a@example.com").exists())

    def test_unattended_creates_once_then_noop(self):
        from django.core.management import call_command

        env = {
            "CIVIC_BOOTSTRAP_SECRET": "s" * 40,
            "CIVIC_ADMIN_PASSWORD": "RootPass9!",
        }
        with mock.patch.dict(os.environ, env):
            call_command(
                "bootstrap_admin",
                email="boot@example.com",
                superuser=True,
                unattended=True,
            )
        user = User.objects.get(email="boot@example.com")
        self.assertTrue(user.is_staff)
        self.assertTrue(user.is_superuser)
        self.assertTrue(user.check_password("RootPass9!"))

        # A second unattended run must NOT create or alter anything.
        with mock.patch.dict(os.environ, env):
            call_command(
                "bootstrap_admin",
                email="second@example.com",
                unattended=True,
            )
        self.assertFalse(
            User.objects.filter(email="second@example.com").exists()
        )
        # And it must never reset the existing password.
        user.refresh_from_db()
        self.assertTrue(user.check_password("RootPass9!"))