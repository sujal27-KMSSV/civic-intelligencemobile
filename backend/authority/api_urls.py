from django.urls import path

from . import api

app_name = "authority_api"

urlpatterns = [
    path("issues/", api.issue_list, name="issue_list"),
    path("issues/<int:pk>/", api.issue_detail, name="issue_detail"),
    path(
        "issues/<int:pk>/transition/",
        api.issue_transition,
        name="transition",
    ),
    path("issues/<int:pk>/resolve/", api.issue_resolve, name="resolve"),
    path("stats/", api.stats, name="stats"),
]