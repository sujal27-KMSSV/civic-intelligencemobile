import 'dart:convert';

import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/features/reporting/report_draft.dart';
import 'package:civic_intelligence/features/reporting/report_repository.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const submissionResponse = {
    'id': 1042,
    'category': 'pothole',
    'confidence': 0.96,
    'severity': 'critical',
    'duplicate': true,
    'duplicate_count': 17,
    'department': 'roads',
    'status': 'reported',
  };

  http.Response jsonResponse(Object body, int status) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json'},
      );

  ApiIssueRepository repositoryWith(http.Response Function() response) =>
      ApiIssueRepository(
        client: ApiClient(
          client: MockClient((request) async => response()),
          authStorage: InMemoryAuthStorage(),
        ),
      );

  ReportDraft completeDraft() => ReportDraft(
        category: 'Pothole',
        image: photoFile(),
        latitude: 28.6139,
        longitude: 77.2090,
        accuracyInMeters: 12,
        address: 'Connaught Place, New Delhi',
        description: 'Pothole near the crossing.',
      );

  test('submitReport posts to the API and returns the parsed issue', () async {
    final repo = repositoryWith(() => jsonResponse(submissionResponse, 201));

    final issue = await repo.submitReport(completeDraft());

    expect(issue.id, '1042');
    expect(issue.status, 'reported');
    expect(issue.statusEnum, IssueStatus.reported);
    expect(issue.analysis?.category, 'Pothole');
    expect(issue.analysis?.confidence, closeTo(0.96, 0.0001));
    expect(issue.analysis?.severity, 'CRITICAL');
    expect(issue.analysis?.isDuplicate, isTrue);
    expect(issue.analysis?.duplicateCount, 17);
    expect(issue.analysis?.department, 'roads');

    // Local draft details are layered on for display purposes.
    expect(issue.description, 'Pothole near the crossing.');
    expect(issue.latitude, closeTo(28.6139, 0.0001));
    expect(issue.longitude, closeTo(77.2090, 0.0001));
    expect(issue.address, 'Connaught Place, New Delhi');
    expect(issue.imageUrl, isNotNull);
  });

  test('fetchMyReports parses the list and sorts newest first', () async {
    final body = [
      {
        'id': 1041,
        'category': 'pothole',
        'severity': 'critical',
        'status': 'reported',
        'created_at': '2026-01-02T09:00:00Z',
        'department': 'roads',
        'duplicate': false,
        'duplicate_count': 0,
        'confidence': 0.96,
      },
      {
        'id': 1042,
        'category': 'street lighting',
        'severity': 'high',
        'status': 'in_progress',
        'created_at': '2026-01-05T09:00:00Z',
        'department': 'Electricity Board',
        'duplicate': true,
        'duplicate_count': 4,
        'confidence': 0.91,
      },
    ];
    final repo = repositoryWith(() => jsonResponse(body, 200));

    final reports = await repo.fetchMyReports();

    expect(reports.length, 2);
    // Newest first.
    expect(reports.first.id, '1042');
    expect(reports.first.status, 'in_progress');
    expect(reports.first.statusEnum, IssueStatus.inProgress);
    expect(reports.first.analysis?.category, 'Street lighting');
    expect(reports.first.analysis?.severity, 'HIGH');
    expect(reports.first.analysis?.isDuplicate, isTrue);
    expect(reports.first.analysis?.duplicateCount, 4);
    expect(reports.first.analysis?.department, 'Electricity Board');
    expect(reports.last.id, '1041');
  });

  test('fetchMyReports maps nested analysis objects', () async {
    final body = [
      {
        'id': 9,
        'status': 'reported',
        'created_at': '2026-01-01T10:00:00Z',
        'analysis': {
          'category': 'Pothole',
          'confidence': 0.9,
          'severity': 'LOW',
          'is_duplicate': false,
          'duplicate_count': 0,
          'department': 'Roads',
        },
      },
    ];
    final repo = repositoryWith(() => jsonResponse(body, 200));

    final reports = await repo.fetchMyReports();

    expect(reports.single.id, '9');
    expect(reports.single.analysis?.category, 'Pothole');
    expect(reports.single.analysis?.severity, 'LOW');
    expect(reports.single.analysis?.department, 'Roads');
    expect(reports.single.analysis?.isDuplicate, isFalse);
  });

  test('fetchMyReports is empty when the backend returns no reports',
      () async {
    final repo = repositoryWith(() => jsonResponse([], 200));
    expect(await repo.fetchMyReports(), isEmpty);
  });

  test('fetchMyReports propagates API failures', () async {
    final repo = repositoryWith(
      () => jsonResponse({'detail': 'Server exploded'}, 500),
    );

    expect(
      () => repo.fetchMyReports(),
      throwsA(isA<ServerException>().having(
        (e) => e.message,
        'message',
        'Server exploded',
      )),
    );
  });

  test('fetchMyReports rejects a non-list response', () async {
    final repo = repositoryWith(() => jsonResponse({'items': []}, 200));

    expect(
      () => repo.fetchMyReports(),
      throwsA(isA<ServerException>()),
    );
  });

  test('submitReport throws when required draft fields are missing', () async {
    final repo = repositoryWith(() => jsonResponse(submissionResponse, 201));
    const incomplete = ReportDraft(category: 'Pothole');

    expect(
      () => repo.submitReport(incomplete),
      throwsA(isA<ServerException>()),
    );
  });

  test('submitReport propagates API failures', () async {
    final repo = repositoryWith(
      () => jsonResponse({'detail': 'Server exploded'}, 500),
    );

    expect(
      () => repo.submitReport(completeDraft()),
      throwsA(isA<ServerException>().having(
        (e) => e.message,
        'message',
        'Server exploded',
      )),
    );
  });

  group('ReportDraft.isReadyToSubmit', () {
    test('false until category, image and coordinates are present', () {
      expect(const ReportDraft().isReadyToSubmit, isFalse);

      final partial = ReportDraft(
        category: 'Pothole',
        image: photoFile(),
        latitude: null,
        longitude: null,
      );
      expect(partial.isReadyToSubmit, isFalse);

      final ready = ReportDraft(
        category: 'Pothole',
        image: photoFile(),
        latitude: 28.6139,
        longitude: 77.2090,
      );
      expect(ready.isReadyToSubmit, isTrue);
    });

    test('clearing location leaves other fields intact', () {
      final cleared = completeDraft().copyWith(clearLocation: true);

      expect(cleared.latitude, isNull);
      expect(cleared.longitude, isNull);
      expect(cleared.accuracyInMeters, isNull);
      expect(cleared.address, isNull);
      expect(cleared.category, 'Pothole');
      expect(cleared.description, 'Pothole near the crossing.');
      expect(cleared.image, isNotNull);
    });
  });
}