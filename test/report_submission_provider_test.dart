import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/features/reporting/report_draft.dart';
import 'package:civic_intelligence/features/reporting/report_draft_provider.dart';
import 'package:civic_intelligence/features/reporting/report_repository.dart';
import 'package:civic_intelligence/features/reporting/report_submission_provider.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

/// Records every client_request_id the submission provider sends and can be
/// scripted to fail the first N submissions (like a timed-out backend).
class _RecordingRepository implements ReportRepository {
  _RecordingRepository({this.failures = 0});

  int failures;
  int calls = 0;
  final List<String?> requestIds = [];

  @override
  Future<Issue> submitReport(ReportDraft draft, {String? clientRequestId}) async {
    requestIds.add(clientRequestId);
    calls++;
    if (calls <= failures) {
      throw const NetworkException(
        message: 'The server took too long to respond.',
        kind: NetworkErrorKind.timeout,
        isRetryable: true,
      );
    }
    return Issue(
      id: 'CI-1043',
      description: draft.description,
      imageUrl: draft.image?.path,
      latitude: draft.latitude,
      longitude: draft.longitude,
      status: IssueStatus.reported.name,
      createdAt: DateTime(2026, 1, 1, 11, 0),
      analysis: const AiAnalysis(
        category: 'Pothole',
        confidence: 1.0,
        severity: 'LOW',
        isDuplicate: false,
        duplicateCount: 0,
        department: 'General Services',
      ),
    );
  }

  @override
  Future<List<Issue>> fetchMyReports() async => const [];

  @override
  Future<void> deleteIssue(String id) async {}

  @override
  Future<Issue> fetchIssue(String id) async =>
      throw UnimplementedError();

  @override
  Future<Issue> updateIssue(
    String id, {
    String? description,
    String? address,
  }) async =>
      throw UnimplementedError();
}

ProviderContainer readyContainer(ReportRepository repo) {
  final container = ProviderContainer(
    overrides: [reportRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(container.dispose);
  container.read(reportDraftProvider.notifier)
    ..selectCategory('Pothole')
    ..setImage(photoFile())
    ..setLocation(testLocation())
    ..setDescription('Pothole near the crossing.');
  return container;
}

void main() {
  test('first submission sends a stable client_request_id', () async {
    final repo = _RecordingRepository();
    final container = readyContainer(repo);

    await container.read(reportSubmissionProvider.notifier).submit();

    expect(container.read(reportSubmissionProvider).phase,
        SubmitPhase.success);
    expect(repo.requestIds, hasLength(1));
    expect(repo.requestIds.single, isNotNull);
    expect(repo.requestIds.single, isNotEmpty);
  });

  test('Try Again reuses the SAME client_request_id after a failure',
      () async {
    final repo = _RecordingRepository(failures: 1);
    final container = readyContainer(repo);
    final notifier = container.read(reportSubmissionProvider.notifier);

    await notifier.submit();
    expect(
        container.read(reportSubmissionProvider).phase, SubmitPhase.failure);

    // "Try Again" calls submit() without reset() — same report lifetime.
    await notifier.submit();
    expect(
        container.read(reportSubmissionProvider).phase, SubmitPhase.success);

    expect(repo.requestIds, hasLength(2));
    expect(repo.requestIds[1], repo.requestIds.first);
  });

  test('Back to Review (reset) starts a fresh client_request_id', () async {
    final repo = _RecordingRepository(failures: 1);
    final container = readyContainer(repo);
    final notifier = container.read(reportSubmissionProvider.notifier);

    await notifier.submit();
    final firstId = repo.requestIds.single;

    // "Back to Review" resets the attempt so an edited draft re-submits
    // under a brand new id.
    notifier.reset();
    await notifier.submit();

    expect(repo.requestIds, hasLength(2));
    expect(repo.requestIds.last, isNotNull);
    expect(repo.requestIds.last, isNot(firstId));
  });

  test('the next report after a success gets a new client_request_id',
      () async {
    final repo = _RecordingRepository(failures: 1);
    final container = readyContainer(repo);
    final notifier = container.read(reportSubmissionProvider.notifier);

    await notifier.submit(); // fails, id kept
    await notifier.submit(); // succeeds with the same id
    final firstId = repo.requestIds.first;

    // Fresh draft for an entirely new report.
    container.read(reportDraftProvider.notifier)
      ..selectCategory('Pothole')
      ..setImage(photoFile())
      ..setLocation(testLocation());
    await notifier.submit();

    expect(repo.requestIds, hasLength(3));
    expect(repo.requestIds.last, isNotNull);
    expect(repo.requestIds.last, isNot(firstId));
  });
}
