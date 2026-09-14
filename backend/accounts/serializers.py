from django.contrib.auth import authenticate
from django.core.exceptions import ValidationError as django_validation
from rest_framework import serializers

from .models import User


class UserSerializer(serializers.ModelSerializer):
    """User payload embedded in the login/register response."""

    class Meta:
        model = User
        fields = ["id", "email", "first_name", "last_name", "phone"]


class RegisterSerializer(serializers.ModelSerializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, trim_whitespace=False)
    phone = serializers.CharField(
        required=False, allow_blank=True, allow_null=True, max_length=20
    )

    class Meta:
        model = User
        fields = ["email", "password", "first_name", "last_name", "phone"]

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError(
                "A user with this email address already exists."
            )
        return value

    def validate_password(self, value):
        from django.contrib.auth.password_validation import validate_password

        try:
            validate_password(value)
        except django_validation as exc:
            raise serializers.ValidationError(list(exc.messages))
        return value

    def create(self, validated_data):
        user = User(**validated_data)
        user.set_password(validated_data["password"])
        user.save()
        return user


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, trim_whitespace=False)

    def validate(self, attrs):
        user = authenticate(
            request=self.context.get("request"),
            username=attrs["email"],
            password=attrs["password"],
        )
        if user is None:
            raise serializers.ValidationError(
                "Unable to log in with provided credentials."
            )
        attrs["user"] = user
        return attrs