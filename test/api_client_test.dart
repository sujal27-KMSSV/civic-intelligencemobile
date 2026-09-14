import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpException;

import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/models/issue.dart';
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

  ApiClient buildApi(http.Client client, {InMemoryAuthStorage? storage}) {
    return ApiClient(
      client: client,
      authStorage: storage ?? InMemoryAuthStorage(),
    );
  }

  test('submitIssue sends multipart fields and the image, parses response',
      () async {
    final file = photoFile();
    late http.Request captured;

    final client = MockClient((request) async {
      captured = request;
      return _jsonResponse({
        'id': 1042,
        'category': 'pothole',
        'confidence': 0.96,
        'severity': 'critical',
        'duplicate': true,
        'duplicate_count': 17,
        'department': 'roads',
        'status': 'reported',
      }, 201);
    });

    final api = buildApi(client);
    final issue = await api.submitIssue(
      image: file,
      latitude: 28.6139,
      longitude: 77.2090,
      description: 'Pothole near the crossing.',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/issues/');
    expect(
      captured.headers['content-type'] ?? '',
      startsWith('multipart/form-data; boundary='),
    );

    final body = utf8.decode(captured.bodyBytes, allowMalformed: true);
    expect(body, contains('name="latitude"'));
    expect(body, contains('28.6139'));
    expect(body, contains('name="longitude"'));
    expect(body, contains('77.209'));
    expect(body, contains('name="description"'));
    expect(body, contains('Pothole near the crossing.'));
    expect(body, contains('name="image"'));

    expect(issue.id, '1042');
    expect(issue.statusEnum, IssueStatus.reported);
    expect(issue.analysis?.category, 'Pothole');
    expect(issue.analysis?.confidence, closeTo(0.96, 0.0001));
    expect(issue.analysis?.severity, 'CRITICAL');
    expect(issue.analysis?.isDuplicate, isTrue);
    expect(issue.analysis?.duplicateCount, 17);
    expect(issue.analysis?.department, 'roads');
  });

  test('submitIssue omits empty description field', () async {
    final file = photoFile();
    late http.Request captured;

    final client = MockClient((request) async {
      captured = request;
      return _jsonResponse({
        'id': 1,
        'category': 'garbage',
        'status': 'reported',
      }, 201);
    });

    final api = buildApi(client);
    await api.submitIssue(
      image: file,
      latitude: 10.0,
      longitude: 20.0,
    );

    final body = utf8.decode(captured.bodyBytes, allowMalformed: true);
    expect(body, isNot(contains('name="description"')));
  });

  test('submitIssue maps non-2xx statuses to AppException', () async {
    final file = photoFile();
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({'detail': 'Invalid image'}),
        422,
        headers: {'content-type': 'application/json'},
      ),
    );

    final api = buildApi(client);
    expect(
      () => api.submitIssue(
        image: file,
        latitude: 10.0,
        longitude: 20.0,
      ),
      throwsA(isA<ServerException>().having(
        (e) => e.message,
        'message',
        'Invalid image',
      )),
    );
  });

  test('submitIssue maps 401 to AuthException', () async {
    final file = photoFile();
    final client = MockClient(
      (request) async => http.Response('', 401),
    );

    final api = buildApi(client);
    expect(
      () => api.submitIssue(image: file, latitude: 1, longitude: 2),
      throwsA(isA<AuthException>()),
    );
  });

  test('submitIssue rejects malformed JSON on success', () async {
    final file = photoFile();
    final client = MockClient(
      (request) async => http.Response('<html>oops</html>', 201),
    );

    final api = buildApi(client);
    expect(
      () => api.submitIssue(image: file, latitude: 1, longitude: 2),
      throwsA(
        isA<ServerException>().having(
          (e) => e.message,
          'message',
          'The server returned an unexpected response.',
        ),
      ),
    );
  });

  test('submitIssue rejects non-object JSON on success', () async {
    final file = photoFile();
    final client = MockClient(
      (request) async => _jsonResponse([1, 2, 3], 201),
    );

    final api = buildApi(client);
    expect(
      () => api.submitIssue(image: file, latitude: 1, longitude: 2),
      throwsA(isA<ServerException>()),
    );
  });

  test('submitIssue surfaces a timeout as a NetworkException', () async {
    final file = photoFile();
    final never = Completer<http.StreamedResponse>();
    final client = _NeverCompletingClient(never.future);

    final api = ApiClient(
      client: client,
      authStorage: InMemoryAuthStorage(),
      timeout: const Duration(milliseconds: 50),
    );
    expect(
      () => api.submitIssue(
        image: file,
        latitude: 1,
        longitude: 2,
        timeout: const Duration(milliseconds: 50),
      ),
      throwsA(
        isA<NetworkException>().having(
          (e) => e.message,
          'message',
          contains('took too long'),
        ),
      ),
    );
  });

  test('fetchMyReports parses a list of flat issue objects', () async {
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/my-reports/');
      return _jsonResponse([
        {
          'id': 1042,
          'category': 'pothole',
          'confidence': 0.96,
          'severity': 'critical',
          'duplicate': true,
          'duplicate_count': 17,
          'department': 'roads',
          'status': 'reported',
          'created_at': '2026-01-02T09:00:00Z',
          'latitude': 28.6139,
          'longitude': 77.2090,
          'address': 'Connaught Place, New Delhi',
        },
      ], 200);
    });

    final api = buildApi(client);
    final issues = await api.fetchMyReports();

    expect(issues.length, 1);
    final issue = issues.first;
    expect(issue.id, '1042');
    expect(issue.statusEnum, IssueStatus.reported);
    expect(issue.analysis?.category, 'Pothole');
    expect(issue.analysis?.confidence, closeTo(0.96, 0.0001));
    expect(issue.analysis?.severity, 'CRITICAL');
    expect(issue.analysis?.isDuplicate, isTrue);
    expect(issue.analysis?.duplicateCount, 17);
    expect(issue.analysis?.department, 'roads');
    expect(issue.createdAt, DateTime.parse('2026-01-02T09:00:00Z'));
    expect(issue.latitude, closeTo(28.6139, 0.0001));
    expect(issue.longitude, closeTo(77.2090, 0.0001));
    expect(issue.address, 'Connaught Place, New Delhi');
  });

  test('fetchMyReports returns an empty list when there are no reports',
      () async {
    final client = MockClient(
      (request) async => _jsonResponse([], 200),
    );

    final api = buildApi(client);
    expect(await api.fetchMyReports(), isEmpty);
  });

  test('fetchMyReports rejects a non-list success body', () async {
    final client = MockClient(
      (request) async => _jsonResponse({'items': []}, 200),
    );

    final api = buildApi(client);
    expect(
      () => api.fetchMyReports(),
      throwsA(isA<ServerException>()),
    );
  });

  test('fetchMyReports surfaces a 401 as AuthException', () async {
    final client = MockClient(
      (request) async => _jsonResponse({'detail': 'Not authenticated'}, 401),
    );

    final api = buildApi(client);
    expect(
      () => api.fetchMyReports(),
      throwsA(isA<AuthException>()),
    );
  });

  test('fetchIssues rejects non-object list items', () async {
    final client = MockClient(
      (request) async => _jsonResponse([
        {'id': 1},
        'not an issue',
      ], 200),
    );

    final api = buildApi(client);
    expect(
      () => api.fetchIssues(),
      throwsA(isA<ServerException>()),
    );
  });

  group('auth headers', () {
    test('includes an Authorization header when a token is stored', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
        token: 'secret-token',
        userId: '1',
        email: 'a@b.com',
      );

      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _jsonResponse([], 200);
      });

      final api = buildApi(client, storage: storage);
      await api.fetchMyReports();

      expect(captured.headers['Authorization'], 'Token secret-token');
    });

    test('uses the Bearer scheme for JWT sessions', () async {
      final storage = InMemoryAuthStorage();
      await storage.saveSession(
        token: 'jwt-access',
        tokenScheme: 'Bearer',
        userId: '1',
        email: 'a@b.com',
      );

      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _jsonResponse([], 200);
      });

      final api = buildApi(client, storage: storage);
      await api.fetchMyReports();

      expect(captured.headers['Authorization'], 'Bearer jwt-access');
    });

    test('omits the Authorization header when signed out', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return _jsonResponse([], 200);
      });

      final api = buildApi(client);
      await api.fetchMyReports();

      expect(captured.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('onUnauthorized', () {
    test('fires when the server returns 401', () async {
      final client = MockClient(
        (request) async => _jsonResponse({'detail': 'expired'}, 401),
      );
      var fired = 0;
      final api = buildApi(client)..onUnauthorized = () => fired++;

      await expectLater(
        api.fetchMyReports(),
        throwsA(isA<AuthException>()),
      );
      expect(fired, 1);
    });

    test('does not fire for other error statuses', () async {
      final client = MockClient(
        (request) async => _jsonResponse({'detail': 'boom'}, 500),
      );
      var fired = 0;
      final api = buildApi(client)..onUnauthorized = () => fired++;

      await expectLater(
        api.fetchMyReports(),
        throwsA(isA<ServerException>()),
      );
      expect(fired, 0);
    });
  });

  group('transport error normalization', () {
    test('normalizes a TLS HandshakeException into a NetworkException',
        () async {
      final client = _ThrowingStreamClient(HandshakeException('bad cert'));
      final api = buildApi(client);

      await expectLater(
        api.fetchMyReports(),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.message,
            'message',
            contains('Secure connection failed'),
          ),
        ),
      );
    });

    test('normalizes a dart:io HttpException into a NetworkException',
        () async {
      final client = _ThrowingStreamClient(HttpException('broken pipe'));
      final api = buildApi(client);

      await expectLater(
        api.fetchMyReports(),
        throwsA(isA<NetworkException>().having(
          (e) => e.message,
          'message',
          contains('Could not reach the server'),
        )),
      );
    });

    test('normalizes an unknown transport error into a NetworkException',
        () async {
      final client = _ThrowingStreamClient(StateError('weird'));
      final api = buildApi(client);

      await expectLater(
        api.fetchMyReports(),
        throwsA(isA<NetworkException>().having(
          (e) => e.message,
          'message',
          contains('connection error'),
        )),
      );
    });

    test('rethrows normalized AppExceptions unchanged', () async {
      final client = MockClient(
        (request) async => _jsonResponse({'detail': 'boom'}, 500),
      );
      final api = buildApi(client);

      await expectLater(
        api.fetchMyReports(),
        throwsA(isA<ServerException>()),
      );
    });
  });

  group('validation errors', () {
    test('maps 400 field errors to ValidationException', () async {
      final client = MockClient(
        (request) async => _jsonResponse({
          'email': ['A user with that email already exists.'],
          'password': ['This password is too short.'],
        }, 400),
      );

      final api = buildApi(client);
      expect(
        () => api.post('/api/auth/register/', body: const {}),
        throwsA(isA<ValidationException>().having(
          (e) => e.fieldErrors['email']?.first,
          'email',
          contains('already exists'),
        )),
      );
    });

    test('keeps detail-string responses as ServerException', () async {
      final client = MockClient(
        (request) async => _jsonResponse({'detail': 'Invalid value'}, 422),
      );

      final api = buildApi(client);
      expect(
        () => api.post('/api/auth/register/', body: const {}),
        throwsA(
          isA<ServerException>().having(
            (e) => e.message,
            'message',
            'Invalid value',
          ),
        ),
      );
    });
  });
}

class _NeverCompletingClient extends http.BaseClient {
  _NeverCompletingClient(this.future);

  final Future<http.StreamedResponse> future;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => future;
}

class _ThrowingStreamClient extends http.BaseClient {
  _ThrowingStreamClient(this.error);

  final Object error;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    throw error;
  }
}