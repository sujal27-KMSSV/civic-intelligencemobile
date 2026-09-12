from django.urls import path

from . import views

app_name = "authority"

urlpatterns = [
    path("", views.dashboard_index, name="dashboard"),
    path("issues/<int:pk>/", views.dashboard_issue_detail, name="issue_detail"),
    path(
        "issues/<int:pk>/transition/",
        views.dashboard_transition,
        name="transition",
    ),
    path("issues/<int:pk>/resolve/", views.dashboard_resolve, name="resolve"),
]