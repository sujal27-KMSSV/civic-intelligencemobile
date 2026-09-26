import 'dart:io';

import 'package:civic_intelligence/core/widgets/issue_card.dart';
import 'package:civic_intelligence/features/feed/issue_feed_repository.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_helpers.dart';

void _step(String s) => debugPrint('[E2E-PROGRESS] $s');

/// Feed repository that can be switched into a deterministic "offline" state.
/// When [fail] is true every fetch throws a network-style [SocketException];
/// otherwise it delegates to the real production [ApiIssueFeedRepository].
class FlakyFeedRepository implements IssueFeedRepository {
  FlakyFeedRepository(this.real);

  final ApiIssueFeedRepository real;
  bool fail = true;

  @override
  Future<List<Issue>> fetchIssues() async {
    if (fail) {
      throw const SocketException('offline');
    }
    return real.fetchIssues();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home feed: offline error state, Retry recovery, relaunch',
      (tester) async {
    final photo = await writeValidPhoto();
    final flaky = FlakyFeedRepository(ApiIssueFeedRepository());

    // ---- Launch with the feed failing --------------------------------------
    _step('reset + pump (fail=true)');
    await resetSession(tester);
    await pumpApp(
      tester,
      photo: photo,
      overrides: [issueFeedRepositoryProvider.overrideWithValue(flaky)],
    );

    _step('A login');
    await login(tester, email: accountAEmail, password: accountAPassword);

    // The feed fetch threw: Home shows the offline EmptyState, not a spinner
    // and not a half-rendered list.
    _step('assert error state');
    await pumpUntil(tester, find.text('Could not load reports'));
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(IssueCard), findsNothing);

    // ---- Network recovers; Retry heals the feed ----------------------------
    _step('retry with recovery');
    flaky.fail = false;
    await tapWidget(tester, find.widgetWithText(FilledButton, 'Retry'));
    await pumpUntil(tester, find.byType(IssueCard));
    expect(find.text('Could not load reports'), findsNothing);
    expect(find.text('Community Reports'), findsOneWidget);

    // ---- Relaunch: stored session restores straight to a healthy feed ------
    _step('relaunch');
    await pumpApp(
      tester,
      photo: photo,
      overrides: [issueFeedRepositoryProvider.overrideWithValue(flaky)],
    );
    await pumpUntil(tester, find.text('Community Reports'));
    await pumpUntil(tester, find.byType(IssueCard));
    expect(find.byType(NavigationBar), findsWidgets);
    expect(find.text('Sign In'), findsNothing);
    expect(find.text('Could not load reports'), findsNothing);
    _step('DONE');
  }, timeout: const Timeout(Duration(minutes: 10)));
}