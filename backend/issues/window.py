"""Retraction window for citizen-submitted reports.

Shared by the ViewSet (which enforces deletes) and the serializer (which tells
the app whether a report may currently be deleted), so the client and server
never disagree about the visible Delete button.
"""

from datetime import timedelta

from django.utils import timezone

# Citizens may retract a mistaken report only shortly after submitting it.
DELETE_WINDOW_MINUTES = 10
DELETE_WINDOW = timedelta(minutes=DELETE_WINDOW_MINUTES)
DELETE_WINDOW_MESSAGE = (
    "Reports can only be deleted within "
    f"{DELETE_WINDOW_MINUTES} minutes of submission."
)


def delete_window_expired(created_at, now=None) -> bool:
    """True when a report may no longer be deleted.

    Uses timezone-aware timestamps and the stored ``created_at`` so manual
    DELETE calls after the window (and stale clients) are rejected too.
    """
    if created_at is None:
        return True
    now = now or timezone.now()
    if now < created_at:
        return True  # clock skew: created_at in the future
    return now - created_at > DELETE_WINDOW