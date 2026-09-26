from django.apps import AppConfig


class GeospatConfig(AppConfig):
    name = "geospat"
    verbose_name = "PostGIS spatial sidecar"

    def ready(self):
        from django.db.models.signals import post_save

        from issues.models import Issue

        from .service import upsert_location

        # Keep the spatial index in sync with issue coordinates. This signal
        # only ever mounts when the app is installed (i.e. PostGIS is real).
        post_save.connect(
            upsert_location,
            sender=Issue,
            dispatch_uid="geospat.upsert_location",
        )