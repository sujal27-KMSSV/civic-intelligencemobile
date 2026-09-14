from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.http import JsonResponse
from django.urls import include, path, re_path
from django.views.static import serve


def health(request):
    return JsonResponse({"status": "ok"})


urlpatterns = [
    path("api/health/", health, name="health"),
    path("admin/", admin.site.urls),
    path("authority/", include("authority.urls")),
    path("api/authority/", include("authority.api_urls")),
    path("api/auth/", include("accounts.urls")),
    path("api/", include("issues.urls")),
]

# Serve uploaded media from MEDIA_ROOT in development (via the standard
# static() helper) and in production (it is a no-op there). On the single
# application instance this is the direct path; at scale swap storage for a
# CDN/object store (see settings.MEDIA_STORAGE_BACKEND).
urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
if not settings.DEBUG:
    urlpatterns += [
        re_path(
            r"^%s(?P<path>.*)$" % settings.MEDIA_URL.lstrip("/"),
            serve,
            kwargs={"document_root": settings.MEDIA_ROOT},
        )
    ]