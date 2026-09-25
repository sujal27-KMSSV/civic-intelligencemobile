"""Rate limiting for the public authentication endpoints.

Login/registration are the only anonymous, high-value attack surfaces, so they
share a strict per-IP budget (10/minute) that blocks password-stuffing and mass
account-creation while never affecting real citizens (a normal session uses << 1
auth request per minute).
"""

from rest_framework.throttling import ScopedRateThrottle


class AuthRateThrottle(ScopedRateThrottle):
    """Applies the shared ``auth`` throttle scope to login/register views.

    DRF resolves the scope from ``view.throttle_scope`` (set on the views) and
    the rate from ``DEFAULT_THROTTLE_RATES["auth"]`` (10/minute by default).
    """