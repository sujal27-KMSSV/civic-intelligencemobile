import 'package:civic_intelligence/features/issues/issue_details_screen.dart';
import 'package:civic_intelligence/features/reporting/report_repository.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

void main() {
  Widget wrap(IssueDetailsScreen screen) {
    return ProviderScope(
      overrides: [
        reportRepositoryProvider.overrideWithValue(FakeReportRepository()),
      ],
      child: MaterialApp(home: screen),
    );
  }

  final fullIssue = Issue(
    id: 'CI-1035',
    description: 'Broken signal at junction. Always red.',
    imageUrl: null,
    latitude: 28.6139,
    longitude: 77.2090,
    address: 'MG Road',
    status: 'in_progress',
    createdAt: DateTime(2026, 1, 5, 18, 30),
    updatedAt: DateTime(2026, 1, 7, 9, 0),
    analysis: const AiAnalysis(
      category: 'Traffic Signal',
      confidence: 0.96,
      severity: 'CRITICAL',
      isDuplicate: true,
      duplicateCount: 17,
      department: 'Traffic Control Dept',
    ),
  );

  testWidgets('renders photo, analysis, details and timeline', (tester) async {
    const size = Size(420, 900);
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(IssueDetailsScreen(issueId: 'CI-1035', issue: fullIssue)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Issue #CI-1035'), findsOneWidget);
    expect(find.text('Traffic Signal'), findsOneWidget);
    expect(find.text('No photo available'), findsOneWidget);

    await bringIntoView(tester, find.text('96%'));
    expect(find.text('96%'), findsOneWidget);
    expect(find.text('CRITICAL'), findsOneWidget);

    await bringIntoView(tester, find.text('Broken signal at junction. Always red.'));
    expect(
      find.text('Broken signal at junction. Always red.'),
      findsOneWidget,
    );
    expect(find.text('MG Road'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('Traffic Control Dept'), findsOneWidget);

    await bringIntoView(tester, find.text('In Progress'));
    expect(find.text('In Progress'), findsNWidgets(2));
    expect(find.text('Reported'), findsOneWidget);
    expect(find.text('5 Jan 2026 · 18:30'), findsWidgets);
    expect(find.text('Resolved'), findsNothing);
  });

  testWidgets('shows duplicate banner when flagged', (tester) async {
    const size = Size(420, 900);
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      wrap(IssueDetailsScreen(issueId: 'CI-1035', issue: fullIssue)),
    );
    await tester.pumpAndSettle();

    await bringIntoView(tester, find.text('17 duplicate reports reported'));
    expect(find.text('17 duplicate reports reported'), findsOneWidget);
  });

  testWidgets('degrades gracefully when the analysis is missing',
      (tester) async {
    const size = Size(420, 900);
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const sparse = Issue(id: 'CI-1', status: 'submitted');
    await tester.pumpWidget(
      wrap(const IssueDetailsScreen(issueId: 'CI-1', issue: sparse)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Other'), findsOneWidget);
    expect(find.text('No photo available'), findsOneWidget);

    await bringIntoView(tester, find.text('Not available yet'));
    expect(find.text('Not available yet'), findsOneWidget);

    await bringIntoView(tester, find.text('No description provided.'));
    expect(find.text('No description provided.'), findsOneWidget);
    expect(find.text('Location unavailable'), findsOneWidget);
  });

  testWidgets('formats coordinates when the address is missing',
      (tester) async {
    const size = Size(420, 900);
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const coords = Issue(
      id: 'CI-2',
      latitude: 28.6139,
      longitude: 77.2090,
      status: 'reported',
      analysis: AiAnalysis(
        category: 'Pothole',
        confidence: 0.9,
        severity: 'HIGH',
        isDuplicate: false,
        duplicateCount: 0,
        department: 'Roads',
      ),
    );
    await tester.pumpWidget(
      wrap(const IssueDetailsScreen(issueId: 'CI-2', issue: coords)),
    );
    await tester.pumpAndSettle();

    await bringIntoView(tester, find.text('28.61390, 77.20900'));
    expect(find.text('28.61390, 77.20900'), findsOneWidget);
    expect(find.text('Roads'), findsOneWidget);
    expect(find.text('HIGH'), findsOneWidget);
    expect(find.text('None'), findsOneWidget);
    expect(find.text('90%'), findsOneWidget);
  });

  testWidgets('shows history note when no dates and unknown status',
      (tester) async {
    const size = Size(420, 900);
    tester.view.physicalSize = size * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const bare = Issue(id: 'CI-3');
    await tester.pumpWidget(
      wrap(const IssueDetailsScreen(issueId: 'CI-3', issue: bare)),
    );
    await tester.pumpAndSettle();

    await bringIntoView(
      tester,
      find.text('Status history is not available for this issue yet.'),
    );
    expect(
      find.text('Status history is not available for this issue yet.'),
      findsOneWidget,
    );
  });

  testWidgets('shows a load-error state when the issue cannot be fetched',
      (tester) async {
    await tester.pumpWidget(
      wrap(const IssueDetailsScreen(issueId: 'CI-999')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load Issue #CI-999'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}