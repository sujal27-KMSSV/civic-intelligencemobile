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

Unattended mode (``--unattended``) exists ONLY for hosts that offer no shell,
SSH or one-off job (e.g. Render's Free web services). It is deliberately the
most restrictive path:

* it refuses to run unless ``CIVIC_BOOTSTRAP_SECRET`` is set to a strong value
  (>= 32 characters) -- a private, backend-only authorization secret;
* it refuses to run unless ``CIVIC_ADMIN_PASSWORD`` is set, so a password is
  never generated and never written to the deploy logs;
* it is ONE-TIME: if any staff account already exists it does nothing and exits
  successfully, so a later re-enable of the variables cannot mint a new admin.

Because the secret cannot be verified against a caller (there is no request),
its role is to ARM the mechanism: without an operator explicitly setting a
long random secret, ``--unattended`` can never create an administrator.
"""

from __future__ import annotations

import os
import secrets
import string

from django.contrib.auth import get_user_model
from django.core.management.base import BaseCommand, CommandError

# Minimum length for the unattended bootstrap authorization secret.
MIN_SECRET_LENGTH = 32


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
        parser.add_argument(
            "--unattended",
            action="store_true",
            help="Shell-less host path: requires CIVIC_BOOTSTRAP_SECRET "
            "(>= 32 chars) and CIVIC_ADMIN_PASSWORD, and refuses to run if a "
            "staff account already exists (one-time).",
        )

    def handle(self, *args, **options):  # noqa: ANN002, ANN003, ANN001
        User = get_user_model()
        unattended = bool(options["unattended"])

        if unattended:
            secret = os.environ.get("CIVIC_BOOTSTRAP_SECRET", "")
            if len(secret) < MIN_SECRET_LENGTH:
                raise CommandError(
                    "Unattended bootstrap requires CIVIC_BOOTSTRAP_SECRET set "
                    f"to at least {MIN_SECRET_LENGTH} characters."
                )
            # One-time: never mint additional admins once one exists.
            if User.objects.filter(is_staff=True).exists():
                self.stdout.write(
                    "Staff account already present; unattended bootstrap is a "
                    "one-time no-op."
                )
                return

        email = (options["email"] or "").strip().lower()
        if not email:
            raise CommandError("--email is required.")

        provided = options["password"] or os.environ.get("CIVIC_ADMIN_PASSWORD")
        if unattended and not provided:
            raise CommandError(
                "Unattended bootstrap requires CIVIC_ADMIN_PASSWORD; a password "
                "is never generated or written to the deploy logs in this mode."
            )
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