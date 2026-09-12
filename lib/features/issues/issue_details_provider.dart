import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/issue.dart';
import '../reporting/report_repository.dart';

/// Fetches the latest details for a single issue by id, so the details screen
/// always reflects the current status from the backend. Invalidate (or use
/// `ref.refresh`) to refetch after a pull-to-refresh.
final issueDetailsProvider = FutureProvider.family<Issue, String>((ref, id) {
  return ref.watch(reportRepositoryProvider).fetchIssue(id);
});