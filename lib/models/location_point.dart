/// A captured geographic point, ready to be sent to the backend.
class LocationPoint {
  const LocationPoint({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    this.address,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;

  /// Accuracy radius in meters, when the platform reports it.
  final double? accuracy;

  /// Human-readable reverse-geocoded label (may be null if geocoding fails).
  final String? address;

  final DateTime capturedAt;

  Map<String, Object?> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'address': address,
      'capturedAt': capturedAt.toIso8601String(),
    };
  }
}