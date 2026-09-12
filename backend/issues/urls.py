from django.urls import include, path
from rest_framework.routers import DefaultRouter

from .views import IssueViewSet, MyReportsView

router = DefaultRouter()
router.register("issues", IssueViewSet, basename="issue")

urlpatterns = [
    path("", include(router.urls)),
    path("my-reports/", MyReportsView.as_view(), name="my-reports"),
]