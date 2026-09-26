from django.urls import path

from .views import NearbyIssuesView

urlpatterns = [
    path("nearby/", NearbyIssuesView.as_view(), name="geospat-nearby"),
]