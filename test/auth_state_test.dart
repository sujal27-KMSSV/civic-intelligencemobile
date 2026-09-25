import 'dart:convert';

import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/features/auth/auth_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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

  ({ProviderContainer container, InMemoryAuthStorage storage}) setupApp(
    Future<http.Response> Function(http.Request) handler, {
    InMemoryAuthStorage? storage,
  }) {
    final store = storage ?? InMemoryAuthStorage();
    final api = ApiClient(
      client: MockClient((request) async => handler(request)),
      authStorage: store,
    );
    final container = ProviderContainer(
      overrides: [
        authStorageProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(api),
      ],
    );
    // Wire the 401 callback exactly as the production provider does so the
    // test exercises the real notice + logout behavior.
    api.onUnauthorized = buildUnauthorizedCallback(
      setNotice: (m) =>
          container.read(authNoticeProvider.notifier).state = m,
      logout: () => container.read(authProvider.notifier).logout(),
    );
    addTearDown(container.dispose);
    return (container: container, storage: store);
  }

  test('restores an authenticated session from storage on startup', () async {
    final storage = InMemoryAuthStorage();
    await storage.saveSession(token: token, userId: '7', email: 'a@b.com');

    final app = setupApp(
      (request) async => _jsonResponse({}, 200),
      storage: storage,
    );
    final container = app.container;

    final state = await container.read(authProvider.future);
    expect(state.status, AuthStatus.authenticated);
    expect(state.user?.id, '7');
    expect(state.user?.email, 'a@b.com');
  });

  test('restores the persisted display name after a restart', () async {
    final storage = InMemoryAuthStorage();
    await storage.saveSession(
      token: token,
      userId: '7',
      email: 'citizen@example.com',
      firstName: 'Jane',
      lastName: 'Doe',
    );

    final app = setupApp(
      (request) async => _jsonResponse({}, 200),
      storage: storage,
    );

    final state = await app.container.read(authProvider.future);
    expect(state.status, AuthStatus.authenticated);
    expect(state.user?.fullName, 'Jane Doe');
  });

  test('a 401 signs the user out and sets the session-expired banner',
      () async {
    final app = setupApp(
      (request) async => _jsonResponse({'token': token, 'user': userJson}, 200),
    );
    final container = app.container;

    await container.read(authProvider.notifier).login('a@b.com', 'secret');
    expect(
      container.read(authProvider).valueOrNull?.status,
      AuthStatus.authenticated,
    );
    expect(container.read(authNoticeProvider), isNull);

    // Simulate a stale-token 401 from the networking layer.
    container.read(apiClientProvider).onUnauthorized?.call();
    await pumpEventQueue();

    expect(container.read(authNoticeProvider), contains('expired'));
    expect(
      container.read(authProvider).valueOrNull?.status,
      AuthStatus.unauthenticated,
    );

    // The next successful sign-in clears the banner.
    await container.read(authProvider.notifier).login('a@b.com', 'secret');
    expect(container.read(authNoticeProvider), isNull);
  });

  test('login clears a stale error before attempting again', () async {
    var fail = true;
    final app = setupApp((request) async {
      if (fail) {
        return _jsonResponse({
          'non_field_errors': ['Unable to log in with provided credentials.'],
        }, 400);
      }
      return _jsonResponse({'token': token, 'user': userJson}, 200);
    });
    final container = app.container;

    await container.read(authProvider.notifier).login('a@b.com', 'wrong');
    expect(container.read(authProvider).hasError, isTrue);

    fail = false;
    // While the second request is in flight the old error must be gone (the
    // form stays on screen in 'unknown' state rather than a stale red banner).
    final inFlight = container.read(authProvider.notifier).login('a@b.com', 'x');
    expect(
      container.read(authProvider).valueOrNull?.status,
      AuthStatus.unknown,
    );
    await inFlight;
    expect(
      container.read(authProvider).valueOrNull?.status,
      AuthStatus.authenticated,
    );
  });

  test('starts unauthenticated when no session exists', () async {
    final app = setupApp((request) async => _jsonResponse({}, 200));
    final state = await app.container.read(authProvider.future);
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.user, isNull);
  });

  test('login succeeds and persists the token', () async {
    final app = setupApp(
      (request) async => _jsonResponse({'token': token, 'user': userJson}, 200),
    );

    await app.container
        .read(authProvider.notifier)
        .login('a@b.com', 'secret');

    final state = app.container.read(authProvider).valueOrNull;
    expect(state?.status, AuthStatus.authenticated);
    expect(state?.user?.fullName, 'Jane Doe');
    expect(await app.storage.readToken(), token);
  });

  test('login failure exposes the error and stays signed out', () async {
    final app = setupApp(
      (request) async => _jsonResponse({
        'non_field_errors': ['Unable to log in with provided credentials.'],
      }, 400),
    );

    await app.container
        .read(authProvider.notifier)
        .login('a@b.com', 'wrong-password');

    final asyncState = app.container.read(authProvider);
    expect(asyncState.hasError, isTrue);
    expect(asyncState.error, isA<ValidationException>());
  });

  test('network failure during login is surfaced', () async {
    final app = setupApp(
      (request) async => throw http.ClientException('boom'),
    );

    await app.container
        .read(authProvider.notifier)
        .login('a@b.com', 'secret');

    final asyncState = app.container.read(authProvider);
    expect(asyncState.hasError, isTrue);
    expect(asyncState.error, isA<NetworkException>());
  });

  test('logout clears the session and state', () async {
    final app = setupApp(
      (request) async => _jsonResponse({'token': token, 'user': userJson}, 200),
    );

    await app.container
        .read(authProvider.notifier)
        .login('a@b.com', 'secret');
    await app.container.read(authProvider.notifier).logout();

    final state = app.container.read(authProvider).valueOrNull;
    expect(state?.status, AuthStatus.unauthenticated);
    expect(await app.storage.readToken(), isNull);
  });
}