import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/location_point.dart';
import 'report_draft.dart';

/// Holds the in-progress report. Consumed by the Report Issue screen and,
/// later, the submission step.
final reportDraftProvider =
    NotifierProvider<ReportDraftNotifier, ReportDraft>(ReportDraftNotifier.new);

class ReportDraftNotifier extends Notifier<ReportDraft> {
  @override
  ReportDraft build() => const ReportDraft();

  void selectCategory(String category) =>
      state = state.copyWith(category: category);

  void setImage(File image) => state = state.copyWith(image: image);

  void clearImage() => state = state.copyWith(clearImage: true);

  void setLocation(LocationPoint location) => state = state.copyWith(
        latitude: location.latitude,
        longitude: location.longitude,
        accuracyInMeters: location.accuracy,
        address: location.address,
      );

  void clearLocation() => state = state.copyWith(clearLocation: true);

  void setDescription(String description) =>
      state = state.copyWith(description: description);

  void reset() => state = const ReportDraft();
}