import 'dart:math';

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
  /// Stable id for the current report "lifetime". Generated once when the first
  /// submit attempt starts and REUSED on every retry, so a report that was
  /// actually saved by the backend but whose response was lost (timeout/mobile
  /// network drop) is not double-created when the user taps Retry.
  ///
  /// Cleared after a confirmed success; the next report gets a fresh id.
  String? _requestId;

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

    _requestId ??= _newRequestId();

    try {
      final issue = await ref
          .read(reportRepositoryProvider)
          .submitReport(draft, clientRequestId: _requestId);
      _requestId = null;
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

  /// A fresh opaque id for one report attempt. High-resolution timestamp +
  /// random entropy; treated by the backend as an opaque string.
  String _newRequestId() {
    final now = DateTime.now();
    final micros = now.microsecondsSinceEpoch;
    final rand = Random().nextInt(0x7fffffff);
    return 'ci-$micros-$rand';
  }

  /// Clears the current attempt. "Try Again" does NOT clear it (same id →
  /// backend de-duplicates a retry that already landed); only this explicit
  /// reset (e.g. "Back to Review", possibly after editing) starts a fresh id.
  void reset() {
    _requestId = null;
    state = const ReportSubmissionState.idle();
  }
}