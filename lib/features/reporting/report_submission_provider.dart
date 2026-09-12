import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/issue.dart';
import '../../services/notification_service.dart';
import '../feed/issue_feed_repository.dart';
import '../issues/my_reports_provider.dart';
import 'report_draft_provider.dart';
import 'report_repository.dart';

enum SubmitPhase { idle, submitting, success, failure }

class ReportSubmissionState {
  const ReportSubmissionState._(this.phase, {this.issue, this.errorMessage});

  const ReportSubmissionState.idle()
      : this._(SubmitPhase.idle);
  const ReportSubmissionState.loading()
      : this._(SubmitPhase.submitting);
  const ReportSubmissionState.success(Issue issue)
      : this._(SubmitPhase.success, issue: issue);
  const ReportSubmissionState.failure(String message)
      : this._(SubmitPhase.failure, errorMessage: message);

  final SubmitPhase phase;
  final Issue? issue;
  final String? errorMessage;

  bool get isSubmitting => phase == SubmitPhase.submitting;
  bool get hasSucceeded => phase == SubmitPhase.success;
}

/// Drives the review screen through idle → submitting → success/failure.
/// Widgets only call [ReportSubmissionNotifier.submit] and watch the state;
/// the actual repository call lives here.
final reportSubmissionProvider = NotifierProvider<ReportSubmissionNotifier,
    ReportSubmissionState>(ReportSubmissionNotifier.new);

class ReportSubmissionNotifier extends Notifier<ReportSubmissionState> {
  @override
  ReportSubmissionState build() => const ReportSubmissionState.idle();

  Future<void> submit() async {
    if (state.isSubmitting) return;
    state = const ReportSubmissionState.loading();

    final draft = ref.read(reportDraftProvider);
    if (!draft.isReadyToSubmit) {
      state = const ReportSubmissionState.failure(
        'Your report is incomplete. Go back and finish it.',
      );
      return;
    }

    try {
      final issue = await ref.read(reportRepositoryProvider).submitReport(draft);
      ref
          .read(notificationServiceProvider)
          .notifyIssueSubmitted(issue);
      ref.read(reportDraftProvider.notifier).reset();
      ref.invalidate(myReportsProvider);
      ref.invalidate(issueFeedProvider);
      state = ReportSubmissionState.success(issue);
    } on AppException catch (error) {
      state = ReportSubmissionState.failure(error.message);
    } catch (_) {
      state = const ReportSubmissionState.failure(
        'Something went wrong. Please try again.',
      );
    }
  }

  void reset() => state = const ReportSubmissionState.idle();
}