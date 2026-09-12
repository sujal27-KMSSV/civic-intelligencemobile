"""Issue-lifecycle state machine.

Machine-readable, identical labels to the Flutter client:
reported, verified, assigned, in_progress, resolved, rejected.
"""

from __future__ import annotations

# Valid transitions for authority-driven status changes.
VALID_TRANSITIONS: dict[str, set[str]] = {
    "reported": {"verified", "rejected"},
    "verified": {"assigned", "in_progress", "rejected"},
    "assigned": {"in_progress", "rejected"},
    "in_progress": {"resolved", "rejected"},
    "resolved": {"in_progress"},  # allow re-open
    "rejected": {"reported"},     # allow re-open after investigation
}


def validate_transition(current: str, target: str) -> str | None:
    """Return an error message if ``current -> target`` is not allowed."""
    if target not in VALID_TRANSITIONS:
        return f"Unknown status: {target}"
    allowed = VALID_TRANSITIONS.get(current)
    if allowed is None:
        return "Unknown current status."
    if target == current:
        return None
    if target not in allowed:
        return (
            f"Cannot move '{current}' -> '{target}'. "
            f"Allowed transitions: {', '.join(sorted(allowed))}"
        )
    return None