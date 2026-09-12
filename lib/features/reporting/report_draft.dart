import 'dart:io';

/// Mutable-in-progress report being assembled by the citizen.
class ReportDraft {
  const ReportDraft({
    this.category,
    this.image,
    this.latitude,
    this.longitude,
    this.accuracyInMeters,
    this.address,
    this.description,
  });

  final String? category;

  /// Captured photo (local file) ready for upload.
  final File? image;
  final double? latitude;
  final double? longitude;
  final double? accuracyInMeters;
  final String? address;
  final String? description;

  /// True when every field required for submission is present.
  bool get isReadyToSubmit =>
      category != null && image != null && latitude != null && longitude != null;

  ReportDraft copyWith({
    String? category,
    File? image,
    double? latitude,
    double? longitude,
    double? accuracyInMeters,
    String? address,
    String? description,
    bool clearImage = false,
    bool clearLocation = false,
    bool clearDescription = false,
  }) {
    return ReportDraft(
      category: category ?? this.category,
      image: clearImage ? null : (image ?? this.image),
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      accuracyInMeters:
          clearLocation ? null : (accuracyInMeters ?? this.accuracyInMeters),
      address: clearLocation ? null : (address ?? this.address),
      description:
          clearDescription ? null : (description ?? this.description),
    );
  }
}