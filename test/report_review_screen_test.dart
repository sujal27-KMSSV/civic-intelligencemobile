import 'package:civic_intelligence/features/reporting/report_draft_provider.dart';
import 'package:civic_intelligence/features/reporting/report_issue_screen.dart';
import 'package:civic_intelligence/features/reporting/report_repository.dart';
import 'package:civic_intelligence/features/reporting/report_review_screen.dart';
import 'package:civic_intelligence/services/location_service.dart';
import 'package:civic_intelligence/services/media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  Widget fullFlowScope(FakeReportRepository repo) {
    final media = FakeMediaService(results: [
      MediaPickResult.success(photoFile()),
    ]);
    final location = FakeLocationService(
      result: LocationResult.success(testLocation()),
    );
    return ProviderScope(
      overrides: [
        mediaServiceProvider.overrideWithValue(media),
        locationServiceProvider.overrideWithValue(location),
        reportRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: ReportIssueScreen()),
    );
  }

  ProviderContainer readyContainer(FakeReportRepository repo) {
    final container = ProviderContainer(
      overrides: [
        reportRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final fine = photoFile();
    container.read(reportDraftProvider.notifier)
      ..selectCategory('Pothole')
      ..setImage(fine)
      ..setLocation(testLocation())
      ..setDescription('Kerb raised after the rain.');
    return container;
  }

  testWidgets('complete flow submits the assembled draft and shows success',
      (tester) async {
    final repo = FakeReportRepository();
    await tester.pumpWidget(fullFlowScope(repo));

    await completeFormViaUi(tester);

    // Set the description through the draft so the bottom action bar is not
    // covered by the text field selection overlay when we tap it.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ReportIssueScreen)),
    );
    container
        .read(reportDraftProvider.notifier)
        .setDescription('Pothole near the crossing.');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Review & Submit'));
    await tester.pumpAndSettle();

    expect(find.text('Review Report'), findsOneWidget);
    expect(find.text('Photo attached'), findsOneWidget);

    await bringIntoView(tester, find.text('Category'));

    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(find.text('Pothole near the crossing.'), findsOneWidget);
    expect(find.text('Kerb raised after the rain.'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Submit Report'));
    await tester.pumpAndSettle();

    // Navigates to the AI result screen.
    expect(find.text('Report CI-1043 submitted'), findsOneWidget);
    expect(find.text('View My Reports'), findsOneWidget);
    expect(find.text('Submit Another'), findsOneWidget);

    await bringIntoView(tester, find.text('Pothole'));
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('100% confidence'), findsOneWidget);
    expect(find.text('LOW'), findsOneWidget);

    await bringIntoView(tester, find.text('New issue'));
    expect(find.text('New issue'), findsOneWidget);

    expect(repo.submitCalls, 1);
    final draft = repo.lastDraft!;
    expect(draft.category, 'Pothole');
    expect(draft.description, 'Pothole near the crossing.');
    expect(draft.latitude, closeTo(28.6139, 0.0001));
    expect(draft.longitude, closeTo(77.2090, 0.0001));
    expect(draft.accuracyInMeters, 12);
    expect(draft.address, 'Connaught Place, New Delhi');
  });

  testWidgets('submit failure shows the API error on the result screen',
      (tester) async {
    final repo = FakeReportRepository(error: Exception('boom'));
    final container = readyContainer(repo);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportReviewScreen()),
      ),
    );

    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();

    expect(repo.submitCalls, 1);
    expect(
      find.textContaining("Couldn't submit your report"),
      findsOneWidget,
    );
    expect(
      find.textContaining('Something went wrong'),
      findsOneWidget,
    );
    expect(find.text('Try Again'), findsOneWidget);
    expect(find.text('Back to Review'), findsOneWidget);
    expect(find.text('Report CI-1043 submitted'), findsNothing);
  });

  testWidgets('warns and disables submit when required fields are missing',
      (tester) async {
    final repo = FakeReportRepository();
    final container = ProviderContainer(
      overrides: [reportRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.read(reportDraftProvider.notifier).selectCategory('Pothole');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportReviewScreen()),
      ),
    );

    expect(find.textContaining('Missing:'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Submit Report'),
    );
    expect(submit.onPressed, isNull);
    expect(repo.submitCalls, 0);
  });

  testWidgets('review shows address, accuracy and description values',
      (tester) async {
    final repo = FakeReportRepository();
    final container = readyContainer(repo);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReportReviewScreen()),
      ),
    );

    await bringIntoView(tester, find.text('Category'));

    expect(find.text('Category'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(find.text('±12 m'), findsOneWidget);
    expect(find.text('Kerb raised after the rain.'), findsOneWidget);
  });
}