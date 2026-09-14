from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.authtoken.models import Token
from rest_framework.test import APITestCase

User = get_user_model()


class AuthApiTests(APITestCase):
    def _register_payload(self, **overrides):
        payload = {
            "first_name": "Jane",
            "last_name": "Doe",
            "email": "citizen@example.com",
            "phone": "+911234567890",
            "password": "SafeCivic#123",
        }
        payload.update(overrides)
        return payload

    def test_register_returns_token_and_user(self):
        response = self.client.post(
            "/api/auth/register/", self._register_payload(), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        data = response.json()
        self.assertIn("token", data)
        self.assertTrue(Token.objects.filter(key=data["token"]).exists())
        self.assertEqual(data["user"]["email"], "citizen@example.com")
        self.assertEqual(data["user"]["first_name"], "Jane")
        self.assertEqual(data["user"]["last_name"], "Doe")
        self.assertEqual(data["user"]["phone"], "+911234567890")
        self.assertNotIn("password", data)
        user = User.objects.get(email="citizen@example.com")
        self.assertTrue(user.check_password("SafeCivic#123"))

    def test_register_duplicate_email_returns_400(self):
        User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        response = self.client.post(
            "/api/auth/register/", self._register_payload(), format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("already exists", response.json()["email"][0])

    def test_register_rejects_invalid_email(self):
        response = self.client.post(
            "/api/auth/register/",
            self._register_payload(email="not-an-email"),
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_login_returns_token_and_user(self):
        User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        response = self.client.post(
            "/api/auth/login/",
            {"email": "citizen@example.com", "password": "secret123"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertIn("token", data)
        self.assertEqual(data["user"]["email"], "citizen@example.com")

    def test_invalid_login_returns_400_non_field_errors(self):
        User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        response = self.client.post(
            "/api/auth/login/",
            {"email": "citizen@example.com", "password": "wrong-password"},
            format="json",
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        body = response.json()
        self.assertIn("non_field_errors", body)
        self.assertIn("Unable to log in", body["non_field_errors"][0])

    def test_login_missing_field_returns_400(self):
        response = self.client.post(
            "/api/auth/login/", {"email": "x@y.com"}, format="json"
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_authenticated_request_with_token(self):
        user = User.objects.create_user(
            email="citizen@example.com", password="secret123"
        )
        token, _ = Token.objects.get_or_create(user=user)
        self.client.credentials(HTTP_AUTHORIZATION=f"Token {token.key}")
        response = self.client.get("/api/my-reports/")
        self.assertEqual(response.status_code, status.HTTP_200_OK)

    def _register_password(self, password):
        return self.client.post(
            "/api/auth/register/",
            self._register_payload(email=f"pw-{abs(hash(password))}@example.com", password=password),
            format="json",
        )

    def test_register_rejects_short_password(self):
        response = self._register_password("Aa1!aa")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("password", response.json())

    def test_register_rejects_missing_uppercase(self):
        response = self._register_password("alllower#123")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("uppercase", response.json()["password"][0].lower())

    def test_register_rejects_missing_lowercase(self):
        response = self._register_password("ALLUPPER#123")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("lowercase", response.json()["password"][0].lower())

    def test_register_rejects_missing_digit(self):
        response = self._register_password("NoDigitsHere#X")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("digit", response.json()["password"][0].lower())

    def test_register_rejects_missing_special(self):
        response = self._register_password("NoSpecialChar123")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn("special", response.json()["password"][0].lower())

    def test_register_rejects_weak_mixed_password(self):
        response = self._register_password("nosecret1")
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        errors = " ".join(response.json()["password"])
        self.assertIn("uppercase", errors)
        self.assertIn("special", errors)

    def test_register_accepts_strong_password(self):
        response = self._register_password("Grid Fix@2026x")
        self.assertEqual(response.status_code, status.HTTP_201_CREATED)