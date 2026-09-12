import 'dart:io';

import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/network/auth_storage.dart';
import 'package:civic_intelligence/features/reporting/report_draft.dart';
import 'package:civic_intelligence/features/reporting/report_repository.dart';
import 'package:civic_intelligence/models/issue.dart';
import 'package:civic_intelligence/models/location_point.dart';
import 'package:civic_intelligence/services/location_service.dart';
import 'package:civic_intelligence/services/media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracy;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 1x1 transparent PNG.
const List<int> kTinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// A tile provider backed by [MockClient], avoiding flutter_test's built-in
/// HTTP stub (which returns 400 for every request) during map widget tests.
TileProvider testTileProvider() => NetworkTileProvider(
      httpClient: MockClient(
        (_) async => http.Response.bytes(kTinyPng, 200),
      ),
    );

/// In-memory session store for tests.
class InMemoryAuthStorage implements AuthStorage {
  String? token;
  String? tokenScheme;
  String? refreshToken;
  String? userId;
  String? email;

  @override
  Future<void> clear() async {
    token = null;
    tokenScheme = null;
    refreshToken = null;
    userId = null;
    email = null;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readTokenScheme() async => tokenScheme;

  @override
  Future<String?> readUserId() async => userId;

  @override
  Future<String?> readUserEmail() async => email;

  /// Convenience for tests (not part of the [AuthStorage] interface).
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> saveSession({
    required String token,
    String? tokenScheme,
    String? refreshToken,
    String? userId,
    String? email,
  }) async {
    this.token = token;
    if (tokenScheme != null) this.tokenScheme = tokenScheme;
    if (refreshToken != null) this.refreshToken = refreshToken;
    if (userId != null) this.userId = userId;
    if (email != null) this.email = email;
  }
}

class FakeMediaService extends MediaService {
  FakeMediaService({this.results = const []});

  final List<MediaPickResult> results;
  int captureCalls = 0;
  int galleryCalls = 0;

  @override
  Future<MediaPickResult> capturePhoto() async {
    final index = captureCalls++;
    return index < results.length ? results[index] : MediaPickResult.cancelled();
  }

  @override
  Future<MediaPickResult> pickFromGallery() async {
    final index = galleryCalls++;
    return index < results.length ? results[index] : MediaPickResult.cancelled();
  }
}

File photoFile() {
  final file = File(
    '${Directory.systemTemp.path}/civic_test_${DateTime.now().microsecondsSinceEpoch}.png',
  );
  file.writeAsBytesSync(kTinyPng);
  return file;
}

class FakeLocationService extends LocationService {
  FakeLocationService({this.result});

  final LocationResult? result;
  int calls = 0;

  @override
  Future<LocationResult> captureCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    bool resolveAddress = true,
  }) async {
    calls++;
    return result ?? LocationResult.unavailable('Fake not configured');
  }
}

LocationPoint testLocation() => LocationPoint(
      latitude: 28.6139,
      longitude: 77.2090,
      accuracy: 12,
      address: 'Connaught Place, New Delhi',
      capturedAt: DateTime(2026, 1, 1, 10, 30),
    );

class FakeReportRepository implements ReportRepository {
  FakeReportRepository({this.error, this.reports = const []});

  final Object? error;
  final List<Issue> reports;
  int submitCalls = 0;
  ReportDraft? lastDraft;

  @override
  Future<List<Issue>> fetchMyReports() async => reports;

  @override
  Future<Issue> fetchIssue(String id) async {
    final error = this.error;
    if (error != null) throw error;
    final matches = reports.where((issue) => issue.id == id);
    if (matches.isNotEmpty) return matches.first;
    throw const ServerException(message: 'Issue not found.', statusCode: 404);
  }

  @override
  Future<Issue> submitReport(ReportDraft draft) async {
    submitCalls++;
    lastDraft = draft;
    final error = this.error;
    if (error != null) throw error;
    return Issue(
      id: 'CI-1043',
      description: draft.description,
      imageUrl: draft.image?.path,
      latitude: draft.latitude,
      longitude: draft.longitude,
      address: draft.address,
      status: IssueStatus.reported.name,
      createdAt: DateTime(2026, 1, 1, 11, 0),
      analysis: AiAnalysis(
        category: draft.category ?? 'Other',
        confidence: 1.0,
        severity: 'LOW',
        isDuplicate: false,
        duplicateCount: 0,
        department: 'Unassigned',
      ),
    );
  }
}

/// Scrolls the list (down, then up) until [finder] is built and on screen,
/// then ensures it is visible. Works with lazy ListViews and alongside the
/// description field's own internal Scrollable.
Future<void> bringIntoView(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pump();
  }
  for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pump();
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> tapInList(WidgetTester tester, Finder finder) async {
  await bringIntoView(tester, finder);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Completes the report form steps (category, photo, location) via the UI.
/// Requires already-overridden services.
Future<void> completeFormViaUi(WidgetTester tester) async {
  await tester.tap(find.text('Pothole'));
  await tester.pump();
  await tapInList(tester, find.text('From Gallery'));
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Add Location'));
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}