from django.conf import settings
from django.db import models


class Issue(models.Model):
    """A citizen-reported civic issue.

    The AI-derived fields (category, confidence, severity, duplicate,
    duplicate_count, department) are intentionally model columns so the future
    AI service can populate them; the MVP stores honest defaults and never
    claims analysis that has not run.
    """

    class Category(models.TextChoices):
        POTHOLE = "pothole", "Pothole"
        ROAD_DAMAGE = "road_damage", "Road damage"
        GARBAGE = "garbage", "Garbage"
        STREETLIGHT = "streetlight", "Streetlight"
        DRAINAGE = "drainage", "Drainage"
        OTHER = "other", "Other"

    class Severity(models.TextChoices):
        LOW = "low", "Low"
        MEDIUM = "medium", "Medium"
        HIGH = "high", "High"
        CRITICAL = "critical", "Critical"

    class Status(models.TextChoices):
        REPORTED = "reported", "Reported"
        VERIFIED = "verified", "Verified"
        ASSIGNED = "assigned", "Assigned"
        IN_PROGRESS = "in_progress", "In progress"
        RESOLVED = "resolved", "Resolved"
        REJECTED = "rejected", "Rejected"

    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="issues",
    )
    image = models.ImageField(upload_to="issues/%Y/%m/%d/")
    description = models.TextField(blank=True, default="")
    address = models.CharField(max_length=255, blank=True, default="")

    # GPS
    latitude = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)

    # Civic-analysis / routed fields. Populated by issues.civic.run_analysis()
    # (honest, rule-based heuristics) or by future trained models -- the API
    # contract and mobile payload are identical either way.
    category = models.CharField(
        max_length=32, choices=Category.choices, default=Category.OTHER
    )
    confidence = models.FloatField(default=0.0)
    severity = models.CharField(
        max_length=16, choices=Severity.choices, default=Severity.LOW
    )
    duplicate = models.BooleanField(default=False)
    duplicate_count = models.PositiveIntegerField(default=0)
    department = models.CharField(
        max_length=64, blank=True, default="Unassigned"
    )
    status = models.CharField(
        max_length=16, choices=Status.choices, default=Status.REPORTED
    )
    duplicate_of = models.ForeignKey(
        "self",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="duplicates",
        db_index=True,
    )
    # Machine-readable analysis detail (severity breakdown, duplicate cluster,
    # engine version) for the authority dashboard. Human display stays honest.
    analysis = models.JSONField(blank=True, default=dict)

    # Resolution lifecycle (authority-driven).
    resolution_image = models.ImageField(
        upload_to="resolution/%Y/%m/%d/", blank=True, null=True
    )
    resolution_notes = models.TextField(blank=True, default="")
    resolved_at = models.DateTimeField(blank=True, null=True)
    # Honest BEFORE/AFTER image comparison (issues.civic.image_similarity).
    resolution_similarity = models.FloatField(blank=True, null=True)

    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [
            models.Index(fields=["category"]),
            models.Index(fields=["status"]),
            models.Index(fields=["reporter", "created_at"]),
        ]

    def __str__(self):
        return f"Issue #{self.pk} ({self.category})"