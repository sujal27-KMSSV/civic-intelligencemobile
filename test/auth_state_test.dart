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