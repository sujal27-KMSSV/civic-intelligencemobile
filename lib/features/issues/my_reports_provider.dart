import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/issue.dart';
import '../../services/notification_service.dart';
import '../reporting/report_repository.dart';

/// The current user's submitted reports, newest first.
///
/// Rebuilds whenever it is invalidated (e.g. after a submission or a pull to
/// refresh) and emits an in-app notification for any report whose status
/// changed since the last fetch.
final myReportsProvider =
    AsyncNotifierProvider<MyReportsNotifier, List<Issue>>(
  MyReportsNotifier.new,
);

class MyReportsNotifier extends AsyncNotifier<List<Issue>> {
  @override
  Future<List<Issue>> build() async {
    final reports = await ref.watch(reportRepositoryProvider).fetchMyReports();
    _notifyStatusChanges(reports);
    return reports;
  }

  void _notifyStatusChanges(List<Issue> reports) {
    final previous = state.valueOrNull;
    if (previous == null || previous.isEmpty || reports.isEmpty) return;

    final previousById = {for (final issue in previous) issue.id: issue};
    final service = ref.read(notificationServiceProvider);

    for (final issue in reports) {
      final old = previousById[issue.id];
      if (old == null) continue;
      final newStatus = issue.statusEnum;
      final oldStatus = old.statusEnum;
      if (newStatus == oldStatus || newStatus == IssueStatus.unknown) continue;
      service.notifyIssueStatusChanged(
        issue,
        from: oldStatus == IssueStatus.unknown ? 'Unknown' : oldStatus.label,
        to: newStatus.label,
      );
    }
  }
}