"""Authority web dashboard (server-rendered, staff-only).

Login via the Django admin login (``/admin/login/``), which is the same
account store as the mobile app. All views use ``staff_member_required``.
"""

from __future__ import annotations

import json

from django.contrib.admin.views.decorators import staff_member_required
from django.http import HttpResponseRedirect
from django.shortcuts import get_object_or_404, render
from django.urls import reverse

from issues.models import Issue

from . import service


@staff_member_required
def dashboard_index(request):
    """Queue list (open, critical-first) + live Leaflet map + stats."""
    issues = (
        Issue.objects.select_related("reporter")
        .exclude(status__in=["resolved", "rejected"])
        .order_by("created_at")
    )
    order = {"critical": 0, "high": 1, "medium": 2, "low": 3, "": 4}
    issues = sorted(issues, key=lambda i: (order.get(i.severity, 4), i.created_at))

    markers = []
    for issue in issues:
        if issue.latitude is None or issue.longitude is None:
            continue
        markers.append({
            "id": issue.id,
            "lat": float(issue.latitude),
            "lng": float(issue.longitude),
            "sev": issue.severity,
            "dup": issue.duplicate_count,
            "desc": (issue.description or "")[:60],
            "url": reverse("authority:issue_detail", args=[issue.id]),
        })

    d = service.stats_with_departments()
    return render(
        request,
        "authority/index.html",
        {
            "issues": issues,
            "stats": d,
            "severity_rank": order,
            "markers": json.dumps(markers),
        },
    )


@staff_member_required
def dashboard_issue_detail(request, pk):
    """Issue detail: analysis breakdown, duplicates, transitions, resolution."""
    issue = get_object_or_404(
        Issue.objects.select_related("reporter", "duplicate_of"), pk=pk
    )
    root = issue.duplicate_of or issue
    duplicates = root.duplicates.exclude(pk=issue.pk).select_related("reporter")
    return render(
        request,
        "authority/detail.html",
        {
            "issue": issue,
            "root": root,
            "duplicates": duplicates,
            "analysis": issue.analysis,
            "similarity_scores": {},
        },
    )


@staff_member_required
def dashboard_transition(request, pk):
    """POST-only lifecycle change from the detail page."""
    issue = get_object_or_404(Issue, pk=pk)
    if request.method == "POST":
        issue, error = service.transition_issue(
            issue, request.POST.get("new_status")
        )
        if error:
            from django.contrib import messages

            messages.error(request, error)
    return HttpResponseRedirect(reverse("authority:issue_detail", args=[pk]))


@staff_member_required
def dashboard_resolve(request, pk):
    """POST-only resolution (multipart) from the detail page."""
    issue = get_object_or_404(Issue, pk=pk)
    if request.method == "POST":
        issue, similarity, error = service.resolve_issue(
            issue,
            request.FILES.get("image"),
            request.POST.get("notes", ""),
        )
        from django.contrib import messages

        if error:
            messages.error(request, error)
        else:
            interp = similarity.get("interpretation", "unavailable")
            messages.success(
                request,
                "Resolution recorded. Image comparison: "
                f"{interp} (similarity "
                f"{round(similarity.get('similarity') or 0, 2)}).",
            )
    return HttpResponseRedirect(reverse("authority:issue_detail", args=[pk]))