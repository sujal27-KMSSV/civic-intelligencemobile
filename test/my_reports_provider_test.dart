import 'package:civic_intelligence/features/issues/my_reports_provider.dart';
import 'package:civic_intelligence/features/notifications/notification_center.dart';
import 'package:civic_intelligence/features/reporting/report_draft.dart';
import 'package:civic_intelligence/features/reporting/report_repository.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MutableReports implements ReportRepository {
  _MutableReports(this._reports);

  List<Issue> _reports;

  @override
  Future<List<Issue>> fetchMyReports() async => List.of(_reports);

  @override
  Future<Issue> fetchIssue(String id) async =>
      _reports.firstWhere((issue) => issue.id == id);

  @override
  Future<Issue> submitReport(ReportDraft draft) async {
    throw UnimplementedError();
  }
}

void main() {
  Issue makeIssue(
    String id,
    String status,
  ) =>
      Issue(id: id, description: 'Pothole', status: status);

  test('refresh emits a notification when a report status changes', () async {
    final repo = _MutableReports([makeIssue('CI-1', 'reported')]);
    final container = ProviderContainer(
      overrides: [reportRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final first = await container.read(myReportsProvider.future);
    expect(first.single.statusEnum, IssueStatus.reported);
    expect(container.read(notificationCenterProvider).notifications, isEmpty);

    repo._reports = [makeIssue('CI-1', 'in_progress')];
    container.invalidate(myReportsProvider);
    final second = await container.read(myReportsProvider.future);
    expect(second.single.statusEnum, IssueStatus.inProgress);

    final notifications =
        container.read(notificationCenterProvider).notifications;
    expect(notifications.length, 1);
    expect(notifications.single.type, AppNotificationType.statusChange);
    expect(notifications.single.title, 'Report CI-1 is now In Progress');
    expect(
      notifications.single.body,
      'Status changed from Reported to In Progress.',
    );
  });

  test('no notification when nothing changed or reads the same status',
      () async {
    final repo = _MutableReports([makeIssue('CI-1', 'reported')]);
    final container = ProviderContainer(
      overrides: [reportRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    await container.read(myReportsProvider.future);
    repo._reports = [makeIssue('CI-1', 'reported')];
    container.invalidate(myReportsProvider);
    await container.read(myReportsProvider.future);

    expect(container.read(notificationCenterProvider).notifications, isEmpty);
  });
}