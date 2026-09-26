"""Backfill the spatial index for all historic issues.

Run once after enabling PostGIS so existing reports are searchable:

    python manage.py geospat_sync

Millions of rows aside, this is idempotent (``update_or_create`` per issue).
"""

from django.core.management.base import BaseCommand

from issues.models import Issue


class Command(BaseCommand):
    help = "Upsert SpatialLocation rows for every issue with valid coordinates."

    def handle(self, *args, **options):  # noqa: ANN002, ANN003, ANN001
        from geospat.service import upsert_location

        issues = Issue.objects.exclude(
            latitude__isnull=True, longitude__isnull=True
        )
        total = issues.count()
        errors = 0
        for idx, issue in enumerate(issues.iterator(chunk_size=500), start=1):
            try:
                upsert_location(issue)
            except Exception:  # noqa: BLE001 - one bad row must not stop the backfill
                errors += 1
                self.stderr.write(
                    self.style.WARNING(f"[{idx}/{total}] failed: issue {issue.id}")
                )
                continue
            if idx % 500 == 0:
                self.stdout.write(f"[{idx}/{total}] synced...")
        self.stdout.write(
            self.style.SUCCESS(
                f"Done: {total - errors}/{total} issues spatialized "
                f"({errors} skipped)."
            )
        )