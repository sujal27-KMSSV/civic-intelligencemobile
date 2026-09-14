import re

from django.core.exceptions import ValidationError
from django.utils.translation import gettext as _


class ComplexityPasswordValidator:
    """Passwords must mix character classes: upper, lower, digit, special."""

    UPPER_RE = re.compile(r"[A-Z]")
    LOWER_RE = re.compile(r"[a-z]")
    DIGIT_RE = re.compile(r"\d")
    SPECIAL_RE = re.compile(r"[^A-Za-z0-9]")
    MIN_LENGTH = 8

    def _missing(self, password):
        checks = []
        if len(password) < self.MIN_LENGTH:
            checks.append(
                _("Your password must be at least %(n)d characters long.")
                % {"n": self.MIN_LENGTH}
            )
        if not self.UPPER_RE.search(password):
            checks.append(_("Your password must contain an uppercase letter."))
        if not self.LOWER_RE.search(password):
            checks.append(_("Your password must contain a lowercase letter."))
        if not self.DIGIT_RE.search(password):
            checks.append(_("Your password must contain a digit."))
        if not self.SPECIAL_RE.search(password):
            checks.append(
                _("Your password must contain a special character (e.g. !@#$).")
            )
        return checks

    def validate(self, password, user=None):
        missing = self._missing(password)
        if missing:
            raise ValidationError(missing, code="password_too_weak")

    def get_help_text(self):
        return _(
            "Your password must be at least 8 characters and include an "
            "uppercase letter, a lowercase letter, a digit and a special "
            "character."
        )