import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/constants/colors.dart';
import 'package:civic_intelligence/core/constants/severity_colors.dart';
import 'package:civic_intelligence/features/feed/issue_feed_repository.dart';
import 'package:civic_intelligence/features/map/map_screen.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:civic_intelligence/services/location_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_utils.dart';

class FakeMapRepository implements IssueFeedRepository {
  FakeMapRepository({this.callsBeforeSuccess = 0, this.issues = const []});

  final int callsBeforeSuccess;
  final List<Issue> issues;
  int fetchCalls = 0;

  @override
  Future<List<Issue>> fetchIssues() async {
    fetchCalls++;
    if (fetchCalls <= callsBeforeSuccess) {
      throw const ServerException(message: 'Server exploded.');
    }
    return issues;
  }
}

void main() {
  const criticalIssue = Issue(
    id: 'CI-1',
    description: 'Deep pothole near the crossing.',
    latitude: 28.6139,
    longitude: 77.2090,
    address: 'MG Road',
    status: 'in_progress',
    analysis: AiAnalysis(
      category: 'Pothole',
      confidence: 0.95,
      severity: 'CRITICAL',
      isDuplicate: true,
      duplicateCount: 10,
      department: 'Roads',
    ),
  );

  const lowIssue = Issue(
    id: 'CI-2',
    description: 'Dim streetlight',
    latitude: 28.6330,
    longitude: 77.2190,
    status: 'reported',
    analysis: AiAnalysis(
      category: 'Streetlight',
      confidence: 0.8,
      severity: 'LOW',
      isDuplicate: false,
      duplicateCount: 0,
      department: 'Power',
    ),
  );

  const noCoordinatesIssue = Issue(
    id: 'CI-3',
    description: 'Missing location',
    status: 'reported',
  );

  Widget buildApp({
    required IssueFeedRepository repo,
    LocationResult? location,
  }) {
    return ProviderScope(
      overrides: [
        issueFeedRepositoryProvider.overrideWithValue(repo),
        locationServiceProvider.overrideWithValue(
          FakeLocationService(result: location),
        ),
      ],
      child: MaterialApp(
        home: MapScreen(tileProvider: testTileProvider()),
      ),
    );
  }

  testWidgets('renders a marker per issue with coordinates plus the user dot',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        repo: FakeMapRepository(
          issues: const [criticalIssue, lowIssue, noCoordinatesIssue],
        ),
        location: LocationResult.success(testLocation()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    expect(find.byKey(const Key('user-location-marker')), findsOneWidget);
    expect(find.text('No issues with locations in your area yet.'),
        findsNothing);
  });

  testWidgets('tapping a marker shows its info and can be dismissed',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        repo: FakeMapRepository(issues: const [criticalIssue]),
        location: LocationResult.success(testLocation()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pumpAndSettle();

    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('10 duplicates'), findsOneWidget);
    expect(find.text('View details'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('View details'), findsNothing);
  });

  testWidgets('View details opens the issue details route', (tester) async {
    final router = GoRouter(
      initialLocation: '/map',
      routes: [
        GoRoute(
          path: '/map',
          builder: (_, __) => MapScreen(tileProvider: testTileProvider()),
        ),
        GoRoute(
          path: '/issue/:id',
          builder: (_, state) => Scaffold(
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
          issueFeedRepositoryProvider.overrideWithValue(
            FakeMapRepository(issues: const [criticalIssue]),
          ),
          locationServiceProvider.overrideWithValue(
            FakeLocationService(result: LocationResult.success(testLocation())),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.location_on).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details'));
    await tester.pumpAndSettle();

    expect(find.text('Detail CI-1'), findsOneWidget);
  });

  testWidgets('shows a notice when there are no located issues',
      (tester) async {
    await tester.pumpWidget(
      buildApp(
        repo: FakeMapRepository(issues: const []),
        location: LocationResult.success(testLocation()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No issues with locations in your area yet.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.location_on), findsNothing);
  });

  testWidgets('shows the error notice and recovers on Retry', (tester) async {
    await tester.pumpWidget(
      buildApp(
        repo: FakeMapRepository(
          callsBeforeSuccess: 1,
          issues: const [criticalIssue],
        ),
        location: LocationResult.success(testLocation()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load issues'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.location_on), findsOneWidget);
    expect(find.text('Could not load issues'), findsNothing);
  });

  testWidgets('shows a notice when permission is denied', (tester) async {
    await tester.pumpWidget(
      buildApp(
        repo: FakeMapRepository(issues: const [criticalIssue]),
        location: LocationResult.permissionDenied(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Location permission denied.'), findsOneWidget);
    expect(find.byKey(const Key('user-location-marker')), findsNothing);
  });

  group('severityColor', () {
    test('maps known severities to palette colours', () {
      expect(severityColor('critical'), AppColors.critical);
      expect(severityColor('HIGH'), AppColors.high);
      expect(severityColor('Medium'), AppColors.medium);
      expect(severityColor('low'), AppColors.low);
    });

    test('falls back to grey for missing or unknown values', () {
      expect(severityColor(null), Colors.grey);
      expect(severityColor(''), Colors.grey);
      expect(severityColor('urgent'), Colors.grey);
    });
  });
}
