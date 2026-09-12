import 'dart:convert';

import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/features/auth/auth_models.dart';
import 'package:civic_intelligence/features/auth/auth_repository.dart';
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

  AuthRepository repoWith(
    http.Response Function(http.Request) handler, {
    InMemoryAuthStorage? storage,
  }) {
    return AuthRepository(
      api: ApiClient(
        client: MockClient((request) async => handler(request)),
        authStorage: storage ?? InMemoryAuthStorage(),
      ),
      storage: storage ?? InMemoryAuthStorage(),
    );
  }

  const token = '9944b09199c62bcf9418ad846dd0e4bbdfc6ee4b';
  const userJson = {
    'id': 7,
    'email': 'citizen@example.com',
    'first_name': 'Jane',
    'last_name': 'Doe',
    'phone': '+911234567890',
  };
  final authResponse = _jsonResponse({'token': token, 'user': userJson}, 200);

  group('login', () {
    test('posts to /api/auth/login/ and persists the session', () async {
      late http.Request captured;
      final storage = InMemoryAuthStorage();
      final repo = repoWith(
        (request) {
          captured = request;
          return authResponse;
        },
        storage: storage,
      );

      final response = await repo.login(const LoginRequest(
        email: 'citizen@example.com',
        password: 'secret123',
      ));

      expect(captured.method, 'POST');
      expect(captured.url.path, '/api/auth/login/');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['email'], 'citizen@example.com');
      expect(body['password'], 'secret123');

      expect(response.token, token);
      expect(response.user?.id, '7');
      expect(response.user?.email, 'citizen@example.com');

      // Persisted for later requests.
      expect(await storage.readToken(), token);
      expect(await storage.readUserId(), '7');
      expect(await storage.readUserEmail(), 'citizen@example.com');
    });

    test('persists a JWT access/refresh session with the Bearer scheme',
        () async {
      final storage = InMemoryAuthStorage();
      final repo = repoWith(
        (request) => _jsonResponse({
          'access': 'jwt-access',
          'refresh': 'jwt-refresh',
          'user': userJson,
        }, 200),
        storage: storage,
      );

      final response = await repo.login(
        const LoginRequest(email: 'a@b.com', password: 'secret123'),
      );

      expect(response.token, 'jwt-access');
      expect(response.tokenScheme, 'Bearer');
      expect(response.refreshToken, 'jwt-refresh');
      expect(await storage.readToken(), 'jwt-access');
      expect(await storage.readTokenScheme(), 'Bearer');
      expect(await storage.readRefreshToken(), 'jwt-refresh');
      expect(await storage.readUserId(), '7');
      expect(await storage.readUserEmail(), 'citizen@example.com');
    });

    test('surface invalid-credential errors', () async {
      final repo = repoWith(
        (request) => _jsonResponse({
          'non_field_errors': ['Unable to log in with provided credentials.'],
        }, 400),
      );

      expect(
        () => repo.login(
          const LoginRequest(email: 'a@b.com', password: 'wrong'),
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.fieldErrors['non_field_errors']?.first,
            'non_field_errors',
            contains('Unable to log in'),
          ),
        ),
      );
    });

    test('surface network failures', () async {
      final repo = AuthRepository(
        api: ApiClient(
          client: MockClient(
            (request) async => throw http.ClientException('boom'),
          ),
          authStorage: InMemoryAuthStorage(),
        ),
        storage: InMemoryAuthStorage(),
      );

      expect(
        () => repo.login(
          const LoginRequest(email: 'a@b.com', password: 'secret123'),
        ),
        throwsA(isA<NetworkException>()),
      );
    });
  });

  group('register', () {
    test('posts to /api/auth/register/ and persists the session', () async {
      late http.Request captured;
      final storage = InMemoryAuthStorage();
      final repo = repoWith(
        (request) {
          captured = request;
          return authResponse;
        },
        storage: storage,
      );

      final response = await repo.register(const RegisterRequest(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'citizen@example.com',
        phone: '+911234567890',
        password: 'secret123',
      ));

      expect(captured.url.path, '/api/auth/register/');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['first_name'], 'Jane');
      expect(body['last_name'], 'Doe');
      expect(body['email'], 'citizen@example.com');
      expect(body['phone'], '+911234567890');
      expect(body['password'], 'secret123');

      expect(response.user?.email, 'citizen@example.com');
      expect(await storage.readToken(), token);
    });

    test('omits an empty phone field', () async {
      late http.Request captured;
      final repo = repoWith((request) {
        captured = request;
        return authResponse;
      });

      await repo.register(const RegisterRequest(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'citizen@example.com',
        password: 'secret123',
      ));

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('phone'), isFalse);
    });

    test('exposes field-level validation errors', () async {
      final repo = repoWith(
        (request) => _jsonResponse({
          'email': ['A user with that email already exists.'],
          'first_name': ['This field may not be blank.'],
        }, 400),
      );

      expect(
        () => repo.register(const RegisterRequest(
          firstName: '',
          lastName: 'Doe',
          email: 'taken@example.com',
          password: 'secret123',
        )),
        throwsA(isA<ValidationException>().having(
          (e) => e.fieldErrors['email']?.first,
          'email error',
          contains('already exists'),
        )),
      );
    });
  });

  group('session lifecycle', () {
    test('restoreSession returns null when no session exists', () async {
      final storage = InMemoryAuthStorage();
      final repo = repoWith((request) => authResponse, storage: storage);

      expect(await repo.restoreSession(), isNull);
    });

    test('restoreSession returns the saved user', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
        token: token,
        userId: '7',
        email: 'citizen@example.com',
      );
      final repo = repoWith((request) => authResponse, storage: storage);

      final user = await repo.restoreSession();
      expect(user?.id, '7');
      expect(user?.email, 'citizen@example.com');
    });

    test('restoreSession is null when the token is missing', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
        token: '',
        userId: '7',
        email: 'citizen@example.com',
      );
      final repo = repoWith((request) => authResponse, storage: storage);

      expect(await repo.restoreSession(), isNull);
    });

    test('logout clears all stored credentials', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
        token: token,
        userId: '7',
        email: 'citizen@example.com',
      );
      final repo = repoWith((request) => authResponse, storage: storage);

      await repo.logout();

      expect(await storage.readToken(), isNull);
      expect(await storage.readUserId(), isNull);
      expect(await storage.readUserEmail(), isNull);
    });

    test('getToken returns the persisted token', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(token: token, userId: '7', email: 'a@b.com');
      final repo = repoWith((request) => authResponse, storage: storage);

      expect(await repo.getToken(), token);
    });
  });
}