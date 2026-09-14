import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Reads `GET /api/issues/` (the public community feed) and sorts newest first.
///
/// The feed is PUBLIC by design: it never falls back to the authenticated
/// user's own reports, so private data can never leak into the community feed.
class ApiIssueFeedRepository implements IssueFeedRepository {
  ApiIssueFeedRepository({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  @override
  Future<List<Issue>> fetchIssues() async {
    final issues = await _client.fetchIssues();
    issues.sort(
      (a, b) => (b.createdAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.createdAt?.millisecondsSinceEpoch ?? 0),
    );
    return issues;
  }
}
