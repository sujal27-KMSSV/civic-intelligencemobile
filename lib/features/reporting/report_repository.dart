import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/api_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import '../../models/issue.dart';
import 'report_draft.dart';

/// Contract for submitting and listing reports.
abstract interface class ReportRepository {
  /// The optional [clientRequestId] lets the caller re-use a stable id when
  /// retrying an uncertain submission, so the backend can de-duplicate and the
  /// user never ends up with two reports from one tap.
  Future<Issue> submitReport(ReportDraft draft, {String? clientRequestId});

  /// Returns the user's previously submitted reports, newest first.
  Future<List<Issue>> fetchMyReports();

  /// Deletes a submitted report. The backend rejects deletes outside the
  /// 10-minute retraction window.
  Future<void> deleteIssue(String id);

  /// Fetches a single issue by id (used by the details screen).
  Future<Issue> fetchIssue(String id);

  /// Updates the editable fields of one of the user's own reports.
  ///
  /// The backend only permits citizens to change `description` and `address`
  /// (coordinates, category and the analysis fields are server-owned). Sends
  /// the returned [Issue] with the server's refreshed flags.
  Future<Issue> updateIssue(
    String id, {
    String? description,
    String? address,
  });
}

final reportRepositoryProvider =
    Provider<ReportRepository>((ref) => ApiIssueRepository());

/// Maps a citizen-facing category label to the backend's enum value.
/// Labels with no backend equivalent fall back to "other".
final Map<String, String> _categoryEnumByLabel = {
  'Pothole': 'pothole',
  'Street Lighting': 'streetlight',
  'Garbage & Waste': 'garbage',
  'Broken Footpath': 'road_damage',
  'Drainage / Sewage': 'drainage',
  'Traffic Signal': 'other',
  'Illegal Dumping': 'other',
  'Other': 'other',
};

String _categoryEnum(String? label) =>
    label == null ? 'other' : (_categoryEnumByLabel[label] ?? 'other');

/// Talks to the Django backend: multipart `POST /api/issues/` for submissions
/// and `GET /api/my-reports/` for the user's report list.
class ApiIssueRepository implements ReportRepository {
  ApiIssueRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<Issue>> fetchMyReports() async {
    final reports = await _client.fetchMyReports();
    reports.sort(
      (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0),
    );
    return reports;
  }

  @override
  Future<Issue> fetchIssue(String id) => _client.fetchIssue(id);

  @override
  Future<void> deleteIssue(String id) => _client.deleteIssue(id);

  @override
  Future<Issue> updateIssue(
    String id, {
    String? description,
    String? address,
  }) async {
    final json = await _client.patch(ApiConstants.issueById(id), body: {
      if (description != null) 'description': description,
      if (address != null) 'address': address,
    });
    return Issue.fromJson(json);
  }

  @override
  Future<Issue> submitReport(ReportDraft draft, {String? clientRequestId}) async {
    final image = draft.image;
    final latitude = draft.latitude;
    final longitude = draft.longitude;
    if (image == null || latitude == null || longitude == null) {
      throw const ServerException(message: 'Your report is incomplete.');
    }

    final reported = await _client.submitIssue(
      image: image,
      latitude: latitude,
      longitude: longitude,
      description: draft.description,
      category: _categoryEnum(draft.category),
      imageSource: draft.imageSource,
      clientRequestId: clientRequestId,
    );

    return Issue(
      id: reported.id,
      description: draft.description,
      imageUrl: image.path,
      latitude: latitude,
      longitude: longitude,
      address: draft.address,
      status: reported.status,
      createdAt: reported.createdAt,
      updatedAt: reported.updatedAt,
      analysis: reported.analysis,
    );
  }
}