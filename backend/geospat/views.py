from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView

from .serializers import NearbyResultSerializer
from .service import DEFAULT_RADIUS_M, InvalidCoordinates, nearby_issues


class NearbyIssuesView(APIView):
    """GET /api/geospat/nearby/?lat=&lon=&radius_m=&limit=

    A genuine PostGIS ``ST_DWithin`` neighbourhood search for open issues,
    ordered by distance. Raises a 503-style error if the spatial app is not
    enabled (the endpoint is simply not routed in that case).
    """

    permission_classes = [AllowAny]

    def get(self, request):
        raw_lat = request.query_params.get("lat")
        raw_lon = request.query_params.get("lon")
        if raw_lat is None or raw_lon is None:
            raise ValidationError({"detail": "lat and lon are required."})
        try:
            result = nearby_issues(
                lat=float(raw_lat),
                lon=float(raw_lon),
                radius_m=float(request.query_params.get("radius_m", DEFAULT_RADIUS_M)),
                limit=int(request.query_params.get("limit", 20) or 20),
            )
        except (InvalidCoordinates, TypeError, ValueError) as exc:
            raise ValidationError({"detail": f"Invalid query: {exc}"})

        payload = [
            {
                "distance_m": item["distance_m"],
                "issue": item["issue"],
            }
            for item in result
        ]
        return Response({"count": len(payload), "results": payload})