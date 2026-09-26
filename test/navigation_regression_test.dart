import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/features/auth/auth_state.dart';
import 'package:civic_intelligence/features/auth/register_screen.dart';
import 'package:civic_intelligence/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

class _HomeAnchor extends StatelessWidget {
  const _HomeAnchor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HOME_ANCHOR')),
      body: Center(
        child: TextButton(
          onPressed: () => context.push('/notifications'),
          child: const Text('OPEN_NOTIFICATIONS_BUTTON'),
        ),
      ),
    );
  }
}

class _LoginAnchor extends StatelessWidget {
  const _LoginAnchor();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('LOGIN_ANCHOR'),
            TextButton(
              onPressed: () => context.pushNamed('register'),
              child: const Text('GO_REGISTER_BUTTON'),
            ),
          ],
        ),
      ),
    );
  }
}

GoRouter makeRouter(String initial) => GoRouter(
      initialLocation: initial,
      routes: [
        GoRoute(path: '/', builder: (_, __) => const _HomeAnchor()),
        GoRoute(
          path: '/notifications',
          builder: (_, __) => const NotificationsScreen(),
        ),
        GoRoute(
          name: 'login',
          path: '/login',
          builder: (_, __) => const _LoginAnchor(),
        ),
        GoRoute(
          name: 'register',
          path: '/register',
          builder: (_, __) => const RegisterScreen(),
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer makeContainer() {
    final storage = InMemoryAuthStorage();
    final api = ApiClient(
      client: MockClient((request) async => http.Response('{}', 200)),
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

  Future<void> pump(
    WidgetTester tester,
    ProviderContainer container,
    String initial,
  ) {
    return tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: makeRouter(initial)),
      ),
    );
  }

  testWidgets('notifications: pushed route pops back to the origin screen',
      (tester) async {
    final container = makeContainer();
    await pump(tester, container, '/');
    await tester.tap(find.text('OPEN_NOTIFICATIONS_BUTTON'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('HOME_ANCHOR'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
  });

  testWidgets('notifications: cold route (no history) falls back to home',
      (tester) async {
    final container = makeContainer();
    await pump(tester, container, '/notifications');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('HOME_ANCHOR'), findsOneWidget);
  });

  testWidgets('register: pushed from login pops back to login', (tester) async {
    final container = makeContainer();
    await pump(tester, container, '/login');
    await tester.pump();

    await tester.tap(find.text('GO_REGISTER_BUTTON'));
    await tester.pumpAndSettle();

    expect(find.text('Create Account'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_ANCHOR'), findsOneWidget);
    expect(find.text('Create Account'), findsNothing);
  });

  testWidgets('register: cold route (no history) falls back to login',
      (tester) async {
    final container = makeContainer();
    await pump(tester, container, '/register');
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN_ANCHOR'), findsOneWidget);
  });
}