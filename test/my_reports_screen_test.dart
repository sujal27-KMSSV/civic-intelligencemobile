import 'package:civic_intelligence/core/widgets/issue_card.dart';
import 'package:civic_intelligence/features/issues/my_reports_screen.dart';
import 'package:civic_intelligence/features/reporting/report_repository.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_utils.dart';

void main() {
  Widget buildApp(FakeReportRepository repo) {
    return ProviderScope(
      overrides: [
        reportRepositoryProvider.overrideWithValue(repo),
      ],
      child: const MaterialApp(home: MyReportsScreen()),
    );
  }

  testWidgets('shows reports returned by the repository with count',
      (tester) async {
    const issue = Issue(
      id: 'CI-1043',
      description: 'Pothole near the crossing.',
      address: 'Connaught Place',
      status: 'submitted',
      analysis: AiAnalysis(
        category: 'Pothole',
        confidence: 1.0,
        severity: 'LOW',
        isDuplicate: false,
        duplicateCount: 0,
        department: 'Unassigned',
      ),
    );
    await tester.pumpWidget(buildApp(FakeReportRepository(reports: [issue])));
    await tester.pumpAndSettle();

    expect(find.text('1 report'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('Pothole near the crossing.'), findsOneWidget);
    expect(find.text('Low'), findsOneWidget);
    expect(find.text('Reported'), findsNWidgets(2));
    expect(find.text('Connaught Place'), findsOneWidget);
    expect(find.text('Uploaded recently'), findsOneWidget);
  });

  testWidgets('card shows severity, date and duplicate count', (tester) async {
    final issue = Issue(
      id: 'CI-1035',
      description: 'Broken signal',
      address: 'MG Road',
      status: 'in_progress',
      createdAt: DateTime(2026, 1, 5, 18, 30),
      analysis: const AiAnalysis(
        category: 'Traffic Signal',
        confidence: 0.8,
        severity: 'HIGH',
        isDuplicate: true,
        duplicateCount: 17,
        department: 'TMC',
      ),
    );
    await tester.pumpWidget(buildApp(FakeReportRepository(reports: [issue])));
    await tester.pumpAndSettle();

    expect(find.text('Traffic Signal'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('5 Jan 2026'), findsOneWidget);
    expect(find.text('17 duplicates'), findsOneWidget);
  });

  testWidgets('empty repository shows the empty state', (tester) async {
    await tester.pumpWidget(buildApp(FakeReportRepository(reports: [])));
    await tester.pumpAndSettle();

    expect(find.text('No reports yet'), findsOneWidget);
    expect(find.text('0 report'), findsNothing);
  });

  testWidgets('filter chips narrow the list by status', (tester) async {
    const submitted = Issue(
      id: 'CI-1043',
      description: 'Fresh pothole',
      status: 'submitted',
    );
    const resolved = Issue(
      id: 'CI-1029',
      description: 'Old bin cleared',
      status: 'resolved',
    );
    await tester.pumpWidget(
      buildApp(FakeReportRepository(reports: [submitted, resolved])),
    );
    await tester.pumpAndSettle();

    final resolvedChip = find.widgetWithText(ChoiceChip, 'Resolved');
    await tester.ensureVisible(resolvedChip);
    await tester.pumpAndSettle();
    await tester.tap(resolvedChip);
    await tester.pumpAndSettle();

    expect(find.text('Old bin cleared'), findsOneWidget);
    expect(find.text('Fresh pothole'), findsNothing);
  });

  testWidgets('tapping a report opens the issue details route', (tester) async {
    const issue = Issue(
      id: 'CI-1043',
      description: 'Pothole near the crossing.',
      status: 'submitted',
    );
    final router = GoRouter(
      initialLocation: '/my-reports',
      routes: [
        GoRoute(
          path: '/my-reports',
          builder: (_, __) => const MyReportsScreen(),
        ),
        GoRoute(
          path: '/issue/:id',
          builder: (_, state) => Scaffold(
            appBar: AppBar(title: const Text('Issue Details')),
            body: Center(
              child: Text('Detail ${state.pathParameters['id']}'),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportRepositoryProvider.overrideWithValue(
            FakeReportRepository(reports: [issue]),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(IssueCard));
    await tester.pumpAndSettle();

    expect(find.text('Issue Details'), findsOneWidget);
    expect(find.text('Detail CI-1043'), findsOneWidget);
  });
}