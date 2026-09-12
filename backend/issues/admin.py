from django.contrib import admin

from .models import Issue


@admin.register(Issue)
class IssueAdmin(admin.ModelAdmin):
    list_display = [
        "id",
        "category",
        "severity",
        "status",
        "department",
        "duplicate_count",
        "reporter",
        "created_at",
    ]
    list_filter = ["status", "category", "severity", "created_at"]
    search_fields = ["id", "description", "address", "reporter__email", "department"]
    list_select_related = ["reporter"]
    readonly_fields = ["created_at", "updated_at"]
    fieldsets = (
        (
            "Reporter",
            {"fields": ("reporter", "status", "department")},
        ),
        (
            "Citizen data",
            {
                "fields": (
                    "description",
                    "address",
                    "latitude",
                    "longitude",
                    "image",
                )
            },
        ),
        (
            "AI / analysis",
            {
                "fields": (
                    "category",
                    "confidence",
                    "severity",
                    "duplicate",
                    "duplicate_count",
                    "duplicate_of",
                )
            },
        ),
        ("Timestamps", {"fields": ("created_at", "updated_at")}),
    )