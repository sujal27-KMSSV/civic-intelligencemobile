import 'package:civic_intelligence/core/widgets/issue_card.dart';
import 'package:civic_intelligence/features/auth/auth_state.dart';
import 'package:civic_intelligence/features/feed/issue_feed_repository.dart';
import 'package:civic_intelligence/features/home/home_screen.dart';
import 'package:civic_intelligence/features/notifications/notifications_screen.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_utils.dart';

class FakeHomeRepository implements IssueFeedRepository {
  FakeHomeRepository({this.error, this.issues = const []});

  final Object? error;
  final List<Issue> issues;
  int fetchCalls = 0;

  @override
  Future<List<Issue>> fetchIssues() async {
    fetchCalls++;
    final error = this.error;
    if (error != null) throw error;
    return issues;
  }
}

void main() {
  final sample = Issue(
    id: 'CI-1042',
    description: 'Pothole near the bus stop.',
    address: 'MG Road',
    status: 'in_progress',
    createdAt: DateTime(2026, 1, 5, 10, 0),
    analysis: const AiAnalysis(
      category: 'Pothole',
      confidence: 0.96,
      severity: 'CRITICAL',
      isDuplicate: false,
      duplicateCount: 0,
      department: 'Roads',
    ),
  );

  Widget buildApp(FakeHomeRepository repo) {
    return ProviderScope(
      overrides: [
        issueFeedRepositoryProvider.overrideWithValue(repo),
        authStorageProvider.overrideWithValue(InMemoryAuthStorage()),
      ],
      child: const MaterialApp(home: HomeScreen()),
    );
  }

  testWidgets('renders reports from the repository with header stats',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600) * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = FakeHomeRepository(
      issues: [sample, const Issue(id: 'CI-1', status: 'resolved')],
    );
    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsOneWidget); // Reports stat
    expect(find.text('1'), findsNWidgets(2)); // Open + Resolved stats
    expect(find.text('Pothole'), findsWidgets);
    expect(find.text('Pothole near the bus stop.'), findsOneWidget);
    expect(find.byType(IssueCard), findsNWidgets(2));
    expect(repo.fetchCalls, 1);
  });

  testWidgets('shows loading then empty state for an empty feed',
      (tester) async {
    await tester.pumpWidget(buildApp(FakeHomeRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No community reports yet'), findsOneWidget);
    expect(find.byType(IssueCard), findsNothing);
  });

  testWidgets('shows an error state with a working retry', (tester) async {
    tester.view.physicalSize = const Size(800, 1400) * tester.view.devicePixelRatio;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final repo = FakeHomeRepository(error: Exception('boom'));
    await tester.pumpWidget(buildApp(repo));
    await tester.pumpAndSettle();

    expect(find.text('Could not load reports'), findsOneWidget);
    expect(repo.fetchCalls, 1);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(repo.fetchCalls, 2);
  });

  testWidgets('notification bell opens the notifications screen',
      (tester) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const HomeScreen(),
        ),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          issueFeedRepositoryProvider.overrideWithValue(
            FakeHomeRepository(issues: [sample]),
          ),
          authStorageProvider.overrideWithValue(InMemoryAuthStorage()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('No notifications yet'), findsOneWidget);
  });
}