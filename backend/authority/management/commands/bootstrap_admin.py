"""Provision the initial staff account for the authority console.

Idempotent: run it any time to create the first staff user, or to promote an
existing citizen/accounts user to staff. The password is taken from
``--password`` or the ``CIVIC_ADMIN_PASSWORD`` environment variable (never
committed to a file); if neither is given a strong random one is generated and
shown exactly once on stdout. Re-running never resets an existing password.

    python manage.py bootstrap_admin --email authority@example.com
    CIVIC_ADMIN_PASSWORD='...' python manage.py bootstrap_admin --email authority@example.com

A staff account is all the authority JSON API needs (``IsAdminUser`` ==
``is_staff``). ``--superuser`` additionally enables the Django admin site for
this account.
"""

from __future__ import annotations

import os
import secrets
import string

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError


def _generate() -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*-_=+"
    return "".join(secrets.choice(alphabet) for _ in range(20))


class Command(BaseCommand):
    help = "Create or promote the staff account for the authority console."

    def add_arguments(self, parser):
        parser.add_argument("--email")
        parser.add_argument(
            "--password",
            help="Plaintext password (also read from CIVIC_ADMIN_PASSWORD "
            "if unset).",
        )
        parser.add_argument(
            "--name", help="Optional display name (First Last)."
        )
        parser.add_argument(
            "--superuser",
            action="store_true",
            help="Also grant is_superuser (Django admin access).",
        )

    def handle(self, *args, **options):  # noqa: ANN002, ANN003, ANN001
        User = get_user_model()
        email = (options["email"] or "").strip().lower()
        if not email:
            raise CommandError("--email is required.")

        provided = options["password"] or os.environ.get("CIVIC_ADMIN_PASSWORD")
        password = provided or _generate()
        generated = provided is None
        # Never echo a password given on the command line back to stdout/meta.
        options["password"] = None

        user = User.objects.filter(email=email).first()
        created = user is None
        if created:
            user = User(email=email, is_active=True)
            user.is_staff = True
            user.is_superuser = bool(options["superuser"])
            if options["name"]:
                parts = options["name"].strip().rsplit(None, 1)
                user.first_name = parts[0]
                user.last_name = parts[1] if len(parts) > 1 else ""
            user.set_password(password)
            user.save()
        else:
            changed = []
            if not user.is_staff:
                user.is_staff = True
                changed.append("is_staff=True")
            if options["superuser"] and not user.is_superuser:
                user.is_superuser = True
                changed.append("is_superuser=True")
            if changed:
                user.save(update_fields=["is_staff", "is_superuser"])

        self.stdout.write(
            self.style.SUCCESS(
                f"Staff account ready: {user.email} "
                f"(staff={user.is_staff}, superuser={user.is_superuser})."
            )
        )
        if created and generated:
            self.stdout.write(
                self.style.WARNING(
                    "Generated one-time password (shown only this once):"
                )
            )
            self.stdout.write(f"  {password}")
            self.stdout.write(
                self.style.WARNING(
                    "Store it in your password manager now. It will not be "
                    "printed again."
                )
            )
        elif created:
            self.stdout.write("Password applied.")
        else:
            self.stdout.write(
                "Account already present. Staff flags updated; the password "
                "is NEVER reset by this command — use `manage.py changepassword "
                "email` if you need to change it."
            )