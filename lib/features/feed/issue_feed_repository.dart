import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_client.dart';
import '../../models/issue.dart';

/// Public civic-issues feed shared by the Home screen, the Map and the splash
/// pre-warm. Reading it through one provider means the endpoint is fetched
/// once per session instead of once per screen.
abstract interface class IssueFeedRepository {
  /// Returns the issues shown on Home and as map markers, newest first.
  Future<List<Issue>> fetchIssues();
}

final issueFeedRepositoryProvider =
    Provider<IssueFeedRepository>((ref) => ApiIssueFeedRepository());

/// The single cached feed. Invalidate to refresh.
final issueFeedProvider = FutureProvider<List<Issue>>((ref) {
  return ref.watch(issueFeedRepositoryProvider).fetchIssues();
});

/// Reads `GET /api/issues/` and sorts newest first. If the list endpoint is
/// missing (HTTP 404), it degrades to the current user's own reports so the
/// feed still renders during demos when only `GET /api/my-reports/` exists.
class ApiIssueFeedRepository implements IssueFeedRepository {
  ApiIssueFeedRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<Issue>> fetchIssues() async {
    List<Issue> issues;
    try {
      issues = await _client.fetchIssues();
    } on ServerException catch (e) {
      if (e.statusCode == 404) {
        issues = await _client.fetchMyReports();
      } else {
        rethrow;
      }
    }
    issues.sort(
      (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0),
    );
    return issues;
  }
}