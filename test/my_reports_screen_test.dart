import 'package:civic_intelligence/core/errors/app_exception.dart';
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

  testWidgets('delete button shown only when the server allows it',
      (tester) async {
    final fresh = Issue(
      id: 'CI-2000',
      description: 'Fresh report',
      status: 'reported',
      createdAt: DateTime.now().toUtc(),
      canDelete: true,
      canEdit: true,
    );
    final stale = Issue(
      id: 'CI-2001',
      description: 'Old report',
      status: 'reported',
      createdAt: DateTime.now().toUtc().subtract(const Duration(minutes: 11)),
      canDelete: false,
    );
    await tester.pumpWidget(
      buildApp(FakeReportRepository(reports: [fresh, stale])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsOneWidget);
    final staleButton = find.ancestor(
      of: find.text('Old report'),
      matching: find.byType(IssueCard),
    );
    expect(
      find.descendant(of: staleButton, matching: find.text('Delete')),
      findsNothing,
    );
  });

  testWidgets('delete button hidden without the server flag', (tester) async {
    const issue = Issue(
      id: 'CI-2002',
      description: 'No timestamp',
      status: 'reported',
    );
    await tester.pumpWidget(buildApp(FakeReportRepository(reports: [issue])));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('cancelling the dialog keeps the report', (tester) async {
    final repo = FakeReportRepository(
      reports: [
        Issue(
          id: 'CI-2003',
          description: 'Keep me',
          status: 'reported',
          createdAt: DateTime.now().toUtc(),
          canDelete: true,
        ),
      ],
    );
    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete this report?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, isEmpty);
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('Report deleted.'), findsNothing);
  });

  testWidgets('confirming deletes the report, refreshes and confirms',
      (tester) async {
    final repo = FakeReportRepository(
      reports: [
        Issue(
          id: 'CI-2004',
          description: 'Remove me',
          status: 'reported',
          createdAt: DateTime.now().toUtc(),
          canDelete: true,
        ),
      ],
    );
    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, {'CI-2004'});
    expect(find.text('Remove me'), findsNothing);
    expect(find.text('No reports yet'), findsOneWidget);
    expect(find.text('Report deleted.'), findsOneWidget);
  });

  testWidgets('delete failure shows the server message', (tester) async {
    final repo = FakeReportRepository(
      reports: [
        Issue(
          id: 'CI-2005',
          description: 'Too late',
          status: 'reported',
          createdAt: DateTime.now().toUtc(),
          canDelete: true,
        ),
      ],
      error: const ServerException(
        message: 'Reports can only be deleted within 10 minutes '
            'of submission.',
        statusCode: 403,
      ),
    );
    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.deletedIds, isEmpty);
    expect(find.text('Too late'), findsOneWidget);
    expect(
      find.text(
        'Reports can only be deleted within 10 minutes of submission.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('edit button shown only when the server allows it',
      (tester) async {
    final editable = Issue(
      id: 'CI-3000',
      description: 'Editable report',
      status: 'reported',
      createdAt: DateTime.now().toUtc(),
      canEdit: true,
    );
    final locked = Issue(
      id: 'CI-3001',
      description: 'Locked report',
      status: 'resolved',
      createdAt: DateTime.now().toUtc(),
      canEdit: false,
    );
    await tester.pumpWidget(
      buildApp(FakeReportRepository(reports: [editable, locked])),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    final lockedCard = find.ancestor(
      of: find.text('Locked report'),
      matching: find.byType(IssueCard),
    );
    expect(
      find.descendant(of: lockedCard, matching: find.text('Edit')),
      findsNothing,
    );
  });

  testWidgets('edit update flow saves and refreshes the report list',
      (tester) async {
    final repo = FakeReportRepository(
      reports: [
        Issue(
          id: 'CI-3002',
          description: 'Original write-up',
          address: 'Old address',
          status: 'reported',
          createdAt: DateTime.now().toUtc(),
          canEdit: true,
        ),
      ],
    );
    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Edit report'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Corrected write-up',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Address'),
      'Corrected place',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Corrected write-up'), findsOneWidget);
    expect(find.text('Corrected place'), findsOneWidget);
    expect(find.text('Report updated.'), findsOneWidget);
    expect(find.text('Original write-up'), findsNothing);
  });

  testWidgets('cancelling the edit dialog keeps the original values',
      (tester) async {
    final repo = FakeReportRepository(
      reports: [
        Issue(
          id: 'CI-3003',
          description: 'Keep as-is',
          status: 'reported',
          createdAt: DateTime.now().toUtc(),
          canEdit: true,
        ),
      ],
    );
    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Keep as-is'), findsOneWidget);
    expect(find.text('Report updated.'), findsNothing);
  });

  testWidgets('coordinates act as the primary location when no address exists',
      (tester) async {
    final issue = Issue(
      id: 'CI-3004',
      description: 'Coordinates only',
      status: 'submitted',
      createdAt: DateTime(2026, 1, 5, 18, 30),
      updatedAt: DateTime(2026, 1, 5, 18, 45),
      latitude: 12.971599,
      longitude: 77.594563,
    );
    await tester.pumpWidget(buildApp(FakeReportRepository(reports: [issue])));
    await tester.pumpAndSettle();

    expect(find.text('12.97160, 77.59456'), findsOneWidget);
    // No secondary coordinate line when the coordinates ARE the location.
    expect(find.byIcon(Icons.pin_drop_outlined), findsNothing);
    expect(find.text('Created 5 Jan 2026 · Updated 5 Jan 2026'), findsOneWidget);
  });

  testWidgets('coordinates are a secondary line beneath a friendly address',
      (tester) async {
    final issue = Issue(
      id: 'CI-3005',
      description: 'Addressed + located',
      status: 'submitted',
      createdAt: DateTime(2026, 1, 5, 18, 30),
      address: 'Connaught Place',
      latitude: 28.6315,
      longitude: 77.2167,
    );
    await tester.pumpWidget(buildApp(FakeReportRepository(reports: [issue])));
    await tester.pumpAndSettle();

    expect(find.text('Connaught Place'), findsOneWidget);
    expect(find.text('28.63150, 77.21670'), findsOneWidget);
  });
}