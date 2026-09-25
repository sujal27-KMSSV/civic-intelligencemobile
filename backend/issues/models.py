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

    class ImageSource(models.TextChoices):
        CAMERA = "camera", "Camera"
        GALLERY = "gallery", "Gallery"

    reporter = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="issues",
    )
    image = models.ImageField(upload_to="issues/%Y/%m/%d/")
    # Client-generated idempotency key: a mobile client that is unsure whether
    # its submission landed (timeout/lost response) can re-post the SAME id and
    # get back the original report instead of creating a duplicate. Opaque,
    # nullable, unique per reporter.
    client_request_id = models.CharField(
        max_length=128,
        blank=True,
        null=True,
        default=None,
        db_index=True,
        help_text="Opaque client-provided idempotency key, unique per reporter.",
    )
    # Provenance: where the attached photo came from (camera capture or
    # gallery selection). Blank for legacy reports created before this field.
    image_source = models.CharField(
        max_length=16,
        choices=ImageSource.choices,
        blank=True,
        default="",
        help_text="Whether the photo was captured on-device or picked from the gallery.",
    )
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
        constraints = [
            # One idempotency key per reporter. The condition keeps NULLs (the
            # normal case — most clients send no key) exempt, since Postgres
            # unique constraints would otherwise treat every NULL as equal.
            models.UniqueConstraint(
                fields=["reporter", "client_request_id"],
                condition=~models.Q(client_request_id__isnull=True),
                name="unique_reporter_request_id",
            ),
        ]

    def __str__(self):
        return f"Issue #{self.pk} ({self.category})"