import 'package:civic_intelligence/features/reporting/report_result_screen.dart';
import 'package:civic_intelligence/features/reporting/report_submission_provider.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripts the submission notifier so the screen can be driven through phase
/// transitions without a real repository.
class _ScriptedSubmissionNotifier extends ReportSubmissionNotifier {
  _ScriptedSubmissionNotifier(this.states);

  final List<ReportSubmissionState> states;
  int _index = 0;

  @override
  ReportSubmissionState build() => states[_index];

  @override
  Future<void> submit() async {
    if (_index + 1 < states.length) _index++;
    state = states[_index];
  }
}

void main() {
  Issue makeIssue({
    double confidence = 0.96,
    String severity = 'CRITICAL',
    bool duplicate = false,
    int duplicateCount = 0,
    String department = 'Roads',
    String status = 'reported',
  }) {
    return Issue(
      id: 'CI-1042',
      description: 'Pothole near the crossing.',
      latitude: 28.6139,
      longitude: 77.2090,
      address: 'Connaught Place, New Delhi',
      status: status,
      analysis: AiAnalysis(
        category: 'Pothole',
        confidence: confidence,
        severity: severity,
        isDuplicate: duplicate,
        duplicateCount: duplicateCount,
        department: department,
      ),
    );
  }

  Future<void> pumpResult(
    WidgetTester tester,
    List<ReportSubmissionState> states,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportSubmissionProvider.overrideWith(
            () => _ScriptedSubmissionNotifier(states),
          ),
        ],
        child: const MaterialApp(home: ReportResultScreen()),
      ),
    );
  }

  testWidgets('success shows the AI analysis result with clear hierarchy',
      (tester) async {
    await pumpResult(
      tester,
      [ReportSubmissionState.success(makeIssue())],
    );

    expect(find.text('Report CI-1042 submitted'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('96% confidence'), findsOneWidget);
    expect(find.text('CRITICAL'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Responsible department'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Responsible department'), findsOneWidget);
    expect(find.text('Roads'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Reported'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('View My Reports'), findsOneWidget);
    expect(find.text('Submit Another'), findsOneWidget);
  });

  testWidgets('duplicate issue shows the duplicate banner with the count',
      (tester) async {
    await pumpResult(
      tester,
      [
        ReportSubmissionState.success(
          makeIssue(duplicate: true, duplicateCount: 17),
        ),
      ],
    );

    expect(find.text('Possible duplicate'), findsOneWidget);
    expect(find.text('17 supporting reports'), findsOneWidget);
    expect(find.text('New issue'), findsNothing);
  });

  testWidgets('new issue is shown as such', (tester) async {
    await pumpResult(tester, [ReportSubmissionState.success(makeIssue())]);

    expect(find.text('New issue'), findsOneWidget);
    expect(find.textContaining('No similar reports'), findsOneWidget);
    expect(find.text('Possible duplicate'), findsNothing);
  });

  testWidgets('low confidence surfaces a manual-review note', (tester) async {
    await pumpResult(
      tester,
      [ReportSubmissionState.success(makeIssue(confidence: 0.52))],
    );

    expect(find.text('52% confidence'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.textContaining('Low similarity'),
      80,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('Low similarity (52%)'), findsOneWidget);
  });

  testWidgets('high confidence does not show the low-confidence note',
      (tester) async {
    await pumpResult(tester, [ReportSubmissionState.success(makeIssue())]);

    expect(find.textContaining('Low similarity'), findsNothing);
  });

  testWidgets('loading state shows a progress indicator', (tester) async {
    await pumpResult(tester, [const ReportSubmissionState.loading()]);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Submitting your report…'), findsOneWidget);
  });

  testWidgets('failure shows the API error and retry returns to success',
      (tester) async {
    await pumpResult(
      tester,
      [
        const ReportSubmissionState.failure('Something went wrong.'),
        ReportSubmissionState.success(makeIssue()),
      ],
    );

    expect(find.text("Couldn't submit your report"), findsOneWidget);
    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Back to Review'), findsOneWidget);

    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('96% confidence'), findsOneWidget);
    expect(find.text('Try Again'), findsNothing);
  });
}