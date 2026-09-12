import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import '../../models/issue.dart';
import 'report_draft.dart';

/// Contract for submitting and listing reports.
abstract interface class ReportRepository {
  Future<Issue> submitReport(ReportDraft draft);

  /// Returns the user's previously submitted reports, newest first.
  Future<List<Issue>> fetchMyReports();

  /// Fetches a single issue by id (used by the details screen).
  Future<Issue> fetchIssue(String id);
}

final reportRepositoryProvider =
    Provider<ReportRepository>((ref) => ApiIssueRepository());

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
  Future<Issue> submitReport(ReportDraft draft) async {
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