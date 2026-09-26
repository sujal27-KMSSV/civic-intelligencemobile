import django.contrib.gis.db.models.fields
import django.db.models.deletion
from django.db import migrations, models


class Migration(migrations.Migration):
    """Initial PostGIS sidecar schema.

    Only applied on a PostgreSQL database with the PostGIS extension
    (``django.contrib.gis.db.backends.postgis``). Written by hand because
    ``makemigrations`` can only emit it on such a database (GDAL + PostGIS
    must be present) -- which is exactly the honest boundary the geospat app
    enforces elsewhere.
    """

    initial = True

    dependencies = [
        ("issues", "0007_issue_priority_model_score_issue_vision_and_more"),
    ]

    operations = [
        migrations.CreateModel(
            name="SpatialLocation",
            fields=[
                (
                    "id",
                    models.AutoField(
                        auto_created=True,
                        primary_key=True,
                        serialize=False,
                        verbose_name="ID",
                    ),
                ),
                (
                    "point",
                    django.contrib.gis.db.models.fields.PointField(
                        geography=True, srid=4326
                    ),
                ),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "issue",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="spatial",
                        to="issues.issue",
                    ),
                ),
            ],
            options={
                "db_table": "geospat_spatial_location",
            },
        ),
    ]