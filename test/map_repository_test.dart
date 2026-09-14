import 'dart:convert';

import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/features/feed/issue_feed_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  http.Response jsonResponse(Object body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  ApiIssueFeedRepository repoWith(
    http.Response Function(http.Request) handler,
  ) {
    return ApiIssueFeedRepository(
      client: ApiClient(
        client: MockClient((request) async => handler(request)),
        authStorage: InMemoryAuthStorage(),
      ),
    );
  }

  test('fetchIssues parses the list from GET /api/issues/', () async {
    late http.Request captured;
    final repo = repoWith((request) {
      captured = request;
      return jsonResponse([
        {
          'id': 1041,
          'status': 'reported',
          'latitude': 28.6139,
          'longitude': 77.2090,
          'category': 'pothole',
          'severity': 'critical',
          'confidence': 0.96,
        },
        {
          'id': 1042,
          'status': 'in_progress',
          'category': 'street lighting',
          'severity': 'low',
        },
      ], 200);
    });

    final issues = await repo.fetchIssues();

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/issues/');
    expect(issues.length, 2);
    expect(issues.first.id, '1041');
    expect(issues.first.latitude, 28.6139);
    expect(issues.first.longitude, 77.2090);
    expect(issues.first.analysis?.severity, 'CRITICAL');
    expect(issues.last.id, '1042');
  });

  test('does NOT fall back to private my-reports when the feed 404s', () async {
    final repo = repoWith(
      (request) => jsonResponse({'detail': 'Not found'}, 404),
    );

    // The public community feed must never silently degrade to the caller's
    // own private reports; a missing feed surfaces the error instead.
    await expectLater(
      repo.fetchIssues(),
      throwsA(isA<ServerException>()),
    );
  });

  test('rethrows non-404 failures', () async {
    final repo = repoWith(
      (request) => jsonResponse({'detail': 'Server exploded'}, 500),
    );

    expect(
      () => repo.fetchIssues(),
      throwsA(isA<ServerException>().having(
        (e) => e.message,
        'message',
        'Server exploded',
      )),
    );
  });
}
