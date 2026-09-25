import 'dart:convert';

import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/features/auth/auth_state.dart';
import 'package:civic_intelligence/features/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

http.Response _jsonResponse(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const token = '9944b09199c62bcf9418ad846dd0e4bbdfc6ee4b';
  const userJson = {
    'id': 7,
    'email': 'citizen@example.com',
    'first_name': 'Jane',
    'last_name': 'Doe',
  };

  ProviderContainer makeContainer(
    Future<http.Response> Function(http.Request) handler,
  ) {
    final storage = InMemoryAuthStorage();
    final api = ApiClient(
      client: MockClient((request) async => handler(request)),
      authStorage: storage,
    );
    final container = ProviderContainer(
      overrides: [
        authStorageProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  GoRouter makeRouter() => GoRouter(
        initialLocation: '/login',
        routes: [
          GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
          GoRoute(path: '/', builder: (_, __) => const Scaffold()),
          GoRoute(
            name: 'register',
            path: '/register',
            builder: (_, __) => const Scaffold(),
          ),
        ],
      );

  Future<void> pumpLogin(WidgetTester tester, ProviderContainer container) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: makeRouter()),
      ),
    );
  }

  testWidgets('shows the session-expired banner when set', (tester) async {
    final container =
        makeContainer((request) async => _jsonResponse({}, 200));
    container.read(authNoticeProvider.notifier).state =
        'Your session has expired. Please sign in again to continue.';

    await pumpLogin(tester, container);
    await tester.pump();

    expect(find.textContaining('session has expired'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    // Clearing the notice hides the banner (e.g. after a successful sign-in).
    container.read(authNoticeProvider.notifier).state = null;
    await tester.pump();
    expect(find.textContaining('session has expired'), findsNothing);
  });

  testWidgets('a successful sign-in clears the notice and navigates away',
      (tester) async {
    final container =
        makeContainer((request) async => _jsonResponse({
              'token': token,
              'user': userJson,
            }, 200));
    container.read(authNoticeProvider.notifier).state =
        'Your session has expired. Please sign in again to continue.';

    await pumpLogin(tester, container);
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).at(0), 'citizen@example.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret123');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(container.read(authNoticeProvider), isNull);
    expect(
      container.read(authProvider).valueOrNull?.status,
      AuthStatus.authenticated,
    );
  });
}