"""Engine v3 tests: embedding signal, renormalization, configurable weights and
the graceful AI-service client (never raises, never fakes).
"""

import io
from unittest import mock

from django.contrib.auth import get_user_model
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase, override_settings
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase
from PIL import Image as PILImage

from . import civic
from .models import Issue

User = get_user_model()

# All five signals equal to 1.0 -> the weighted score equals the sum of weights.
UNIFORM = {
    "lat1": 28.6139, "lon1": 77.2090,
    "lat2": 28.6139, "lon2": 77.2090,
    "category1": "pothole", "category2": "pothole",
    "text1": "deep pothole near crossing", "text2": "deep pothole near crossing",
    "image_sim": 1.0,
}


class EmbeddingUnitTests(SimpleTestCase):
    def test_identical_normalized_vectors_have_cosine_one(self):
        self.assertEqual(civic.embedding_cosine([1.0, 0.0, 0.0], [1.0, 0.0, 0.0]), 1.0)

    def test_orthogonal_vectors_have_cosine_zero(self):
        self.assertEqual(civic.embedding_cosine([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]), 0.0)

    def test_dimension_mismatch_returns_none(self):
        self.assertIsNone(civic.embedding_cosine([1.0, 0.0], [1.0]))

    def test_empty_side_returns_none(self):
        self.assertIsNone(civic.embedding_cosine([], [1.0, 0.0]))
        self.assertIsNone(civic.embedding_cosine([1.0, 0.0], None))


class DuplicateScoreV3Tests(SimpleTestCase):
    def test_all_five_signals_combined(self):
        result = civic.duplicate_similarity_score(
            **UNIFORM, embedding_sim=1.0
        )
        self.assertEqual(result["score"], 1.0)
        names = {s["name"] for s in result["signals"]}
        self.assertEqual(
            names, {"gps", "category", "text", "image", "embedding"}
        )

    def test_embedding_signal_lifts_score_when_classic_signals_disagree(self):
        base = dict(
            UNIFORM,
            category2="other",
            text2="completely unrelated words here",
            image_sim=0.2,
        )
        classic = civic.duplicate_similarity_score(**base, embedding_sim=None)
        with_emb = civic.duplicate_similarity_score(**base, embedding_sim=0.9)
        self.assertGreater(with_emb["score"], classic["score"])

    def test_missing_embedding_renormalizes_other_weights(self):
        # With no embedding, active weights renormalize so an otherwise
        # identical report still scores 1.0 (never lowered by the absence of
        # the AI signal).
        result = civic.duplicate_similarity_score(**UNIFORM, embedding_sim=None)
        self.assertAlmostEqual(result["score"], 1.0, places=3)
        embedding_signal = [
            s for s in result["signals"] if s["name"] == "embedding"
        ]
        self.assertEqual(embedding_signal[0]["value"], None)

    def test_configurable_weights_via_settings(self):
        overrides = {
            "gps": 0.1, "category": 0.1, "text": 0.1,
            "image": 0.1, "embedding": 0.6,
        }
        with override_settings(CIVIC_DUPLICATE_WEIGHTS=overrides):
            result = civic.duplicate_similarity_score(
                **UNIFORM, embedding_sim=1.0)
        self.assertAlmostEqual(result["score"], 1.0, places=3)

        # Missing photo + missing embedding renormalize to the live weights.
        with override_settings(CIVIC_DUPLICATE_WEIGHTS=overrides):
            reduced = civic.duplicate_similarity_score(
                **dict(UNIFORM, image_sim=None), embedding_sim=None)
        self.assertAlmostEqual(reduced["score"], 1.0, places=3)
        self.assertEqual(set(reduced["weights"]), {"gps", "category", "text"})

        # A photo-present but unrelated scene is a real disagreement, so its
        # weight stays but contributes 0 (not treated as missing data).
        with override_settings(CIVIC_DUPLICATE_WEIGHTS=overrides):
            no_emb = civic.duplicate_similarity_score(
                **dict(UNIFORM, image_sim=0.0), embedding_sim=None)
        self.assertAlmostEqual(no_emb["score"], 0.75, places=3)

    def test_hard_gps_veto_still_applies(self):
        result = civic.duplicate_similarity_score(
            lat1=28.6139, lon1=77.2090,
            lat2=28.6300, lon2=77.2200,
            category1="pothole", category2="pothole",
            text1="a", text2="a", image_sim=1.0, embedding_sim=1.0,
        )
        self.assertEqual(result["score"], 0.0)
        self.assertEqual(result["signals"], [])


class AiClientGracefulTests(SimpleTestCase):
    @override_settings(AI_SERVICE_URL="")
    def test_image_analysis_returns_none_when_not_configured(self):
        from .ai import image_analysis

        self.assertIsNone(image_analysis("issues/x.png"))

    @override_settings(AI_SERVICE_URL="http://ai.test:8010")
    @mock.patch("issues.civic._read_saved_image", return_value=None)
    def test_image_analysis_returns_none_on_unreadable_image(self, _read):
        from .ai import image_analysis

        self.assertIsNone(image_analysis("issues/x.png"))

    @override_settings(AI_SERVICE_URL="http://ai.test:8010")
    @mock.patch("issues.ai._post", side_effect=ConnectionError("down"))
    @mock.patch("issues.civic._read_saved_image", return_value=b"fakebytes")
    def test_image_analysis_never_raises_on_network_failure(self, _read, _post):
        from .ai import image_analysis

        self.assertIsNone(image_analysis("issues/x.png"))

    @override_settings(AI_SERVICE_URL="http://ai.test:8010")
    @mock.patch("issues.ai._post", side_effect=ConnectionError("down"))
    def test_priority_predict_never_raises_on_network_failure(self, _post):
        from .ai import priority_predict

        self.assertIsNone(
            priority_predict(severity="high", duplicate_count=2, age_hours=3,
                             is_master=False)
        )


def _png_bytes():
    buf = io.BytesIO()
    PILImage.new("RGB", (480, 360), (90, 120, 150)).save(buf, format="PNG")
    return buf.getvalue()


def _dedup_embedding(value: float) -> list[float]:
    """A small deterministic, L2-normalized 4-dim vector."""
    norm = abs(value) or 1.0
    return [round(value / norm, 6), 0.0, 0.0, 0.0]


class IssueAIIntegrationTests(APITestCase):
    def setUp(self):
        self.user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        self.token, _ = Token.objects.get_or_create(user=self.user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {self.token.key}")

    def _png(self):
        return SimpleUploadedFile("photo.png", _png_bytes(),
                                  content_type="image/png")

    def _multipart(self, **overrides):
        data = {
            "latitude": "28.6139",
            "longitude": "77.2090",
            "description": "Pothole near the crossing.",
        }
        data.update(overrides)
        data.setdefault("image", self._png())
        return data

    @override_settings(AI_SERVICE_URL="http://ai.test:8010")
    @mock.patch("issues.ai.priority_predict", return_value={
        "score": 88.5, "label": "critical",
        "model": "gradient-boosting-priority-v1",
        "honest_note": "Prototype.",
        "explanation": {"method": "attribution"},
    })
    @mock.patch("issues.ai.image_analysis", return_value={
        "embedding": {"model": "mobilenet_v3_small", "values": _dedup_embedding(1.0)},
        "detections": [{"label": "car", "confidence": 0.9, "box": [1, 2, 3, 4]}],
        "classifier": {"model": "resnet18", "top": [
            {"label": "street sign", "score": 0.7}, {"label": "car", "score": 0.2}
        ]},
        "notes": ["YOLO detection uses COCO pretrained labels (generic objects only)."],
    })
    def test_create_with_ai_payload_populates_vision_and_ml_score(
        self, _img_analysis, _priority
    ):
        response = self.client.post(
            "/api/issues/", self._multipart(), format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        body = response.json()

        self.assertEqual(
            body["vision"]["status"], "ok",
            "AI sidecar payload must be stored, not fabricated",
        )
        self.assertEqual(
            body["vision"]["models"]["embedding"], "mobilenet_v3_small"
        )
        self.assertEqual(
            body["vision"]["classifier_labels"], ["street sign", "car"]
        )
        self.assertEqual(body["priority_model_score"], 88.5)

        db = Issue.objects.get(id=body["id"])
        self.assertEqual(db.vision_embedding, _dedup_embedding(1.0))
        self.assertEqual(db.analysis["engine"], "rule-based-civic-analysis-v3")
        self.assertEqual(
            db.vision["priority_model"]["label"], "critical"
        )

    @override_settings(AI_SERVICE_URL="http://ai.test:8010")
    @mock.patch("issues.ai.priority_predict", return_value=None)
    @mock.patch("issues.ai.image_analysis", return_value={
        "embedding": {"model": "mobilenet_v3_small", "values": _dedup_embedding(1.0)},
        "detections": [],
        "classifier": None,
        "notes": [],
    })
    def test_embedding_signal_merges_same_photo_duplicates(
        self, _img_analysis, _priority
    ):
        """Two identical submissions (same photo embedding, location, category,
        description) must merge into one cluster."""
        first = self.client.post(
            "/api/issues/", self._multipart(), format="multipart"
        ).json()
        self.assertEqual(first["duplicate"], False)

        second = self.client.post(
            "/api/issues/", self._multipart(), format="multipart"
        ).json()
        self.assertEqual(second["duplicate"], True, "identical photo+embedding")
        self.assertEqual(second["duplicate_count"], 2)
        db = Issue.objects.get(id=second["id"])
        names = {
            s["name"]
            for s in db.analysis["duplicate"]["evidence"]
        }
        self.assertIn("embedding", names, "embedding signal drives the merge")

    @override_settings(AI_SERVICE_URL="")
    def test_without_ai_service_stays_rule_based_v3(self):
        response = self.client.post(
            "/api/issues/", self._multipart(), format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        body = response.json()
        self.assertEqual(body["vision"]["status"], "not_analyzed")
        self.assertIsNone(body["priority_model_score"])
        db = Issue.objects.get(id=body["id"])
        self.assertEqual(db.analysis["engine"], "rule-based-civic-analysis-v3")

    @override_settings(AI_SERVICE_URL="http://ai.test:8010")
    @mock.patch("issues.ai.priority_predict", return_value=None)
    @mock.patch("issues.ai.image_analysis", return_value=None)
    def test_ai_down_degrades_gracefully(self, _img_analysis, _priority):
        response = self.client.post(
            "/api/issues/", self._multipart(), format="multipart"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        body = response.json()
        self.assertEqual(body["vision"]["status"], "unavailable")
        self.assertIsNone(body["priority_model_score"])
        db = Issue.objects.get(id=body["id"])
        self.assertEqual(db.analysis["engine"], "rule-based-civic-analysis-v3")

    @override_settings(AI_SERVICE_URL="")
    def test_vision_fields_default_when_not_analyzed(self):
        issue = Issue.objects.create(
            reporter=self.user,
            image=self._png(),
            description="Pothole near the crossing.",
            latitude="28.6139",
            longitude="77.2090",
        )
        civic.run_analysis(issue)
        issue.refresh_from_db()
        self.assertEqual(issue.vision["status"], "not_analyzed")
        self.assertEqual(issue.vision_embedding, [])
        self.assertIsNone(issue.priority_model_score)