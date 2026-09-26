import 'dart:io';

import 'package:civic_intelligence/main.dart' as app;
import 'package:civic_intelligence/models/location_point.dart';
import 'package:civic_intelligence/services/location_service.dart';
import 'package:civic_intelligence/services/media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracy;
import 'package:integration_test/integration_test.dart';

import 'e2e_helpers.dart';

class _FakeMediaService extends MediaService {
  _FakeMediaService(this.file);

  final File file;

  @override
  Future<MediaPickResult> capturePhoto() async =>
      MediaPickResult.success(file);

  @override
  Future<MediaPickResult> pickFromGallery() async =>
      MediaPickResult.success(file);
}

class _FakeLocationService extends LocationService {
  @override
  Future<LocationResult> captureCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    bool resolveAddress = true,
  }) async {
    return LocationResult.success(LocationPoint(
      latitude: 28.6139,
      longitude: 77.2090,
      accuracy: 12,
      address: 'Connaught Place, New Delhi',
      capturedAt: DateTime(2026, 1, 1, 10, 30),
    ));
  }
}

/// Pumps frames (real time on a device) until [finder] matches, or fails.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 40),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for: $finder');
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('on-device civic flow: register, login, report, my reports',
      (tester) async {
    const storage = FlutterSecureStorage();
    await storage.deleteAll();

    final photo = await writeValidPhoto();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaServiceProvider.overrideWithValue(_FakeMediaService(photo)),
          locationServiceProvider.overrideWithValue(_FakeLocationService()),
        ],
        child: const app.FixMyGridApp(),
      ),
    );

    // Clean start: splash quickly redirects to the login screen.
    await _pumpUntil(tester, find.text('Sign In'));
    expect(find.byType(NavigationBar), findsNothing);

    // ---- REGISTER -----------------------------------------------------------
    await _tap(tester, find.text('Create Account'));
    await _pumpUntil(tester, find.text('Register'));

    final email = 'e2e${DateTime.now().millisecondsSinceEpoch}@example.com';
    const password = 'P@ssw0rd!2026';
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'E2E');
    await tester.enterText(fields.at(1), 'Flow');
    await tester.enterText(fields.at(2), email);
    await tester.enterText(fields.at(3), '+911234567890');
    await tester.enterText(fields.at(4), password);
    await tester.enterText(fields.at(5), password);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));

    await _tap(tester, find.text('Register'));

    // Authenticated session: home screen (shell) appears.
    await _pumpUntil(tester, find.text('Community Reports'));
    expect(find.byType(NavigationBar), findsWidgets);

    // ---- LOGOUT -------------------------------------------------------------
    await _tap(tester, find.text('Profile'));
    await _pumpUntil(tester, find.text('Logout'));

    await _tap(tester, find.text('Logout'));
    await _pumpUntil(
      tester,
      find.descendant(of: find.byType(AlertDialog), matching: find.text('Logout')),
    );
    await _tap(
      tester,
      find
          .descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Logout'),
          )
          .last,
    );

    await _pumpUntil(tester, find.text('Sign In'));
    expect(find.byType(NavigationBar), findsNothing);

    // ---- LOGIN --------------------------------------------------------------
    final loginFields = find.byType(TextFormField);
    await tester.enterText(loginFields.at(0), email);
    await tester.enterText(loginFields.at(1), password);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    await _tap(tester, find.text('Sign In'));

    await _pumpUntil(tester, find.text('Community Reports'));
    expect(find.byType(NavigationBar), findsWidgets);

    // ---- REPORT AN ISSUE ----------------------------------------------------
    await _tap(tester, find.text('Report'));
    await _pumpUntil(tester, find.text('What did you find?'));
    expect(find.text('Report Issue'), findsOneWidget);

    await _tap(tester, find.text('Pothole'));
    await tester.pump(const Duration(milliseconds: 300));

    await _tap(tester, find.text('From Gallery'));
    await _pumpUntil(
      tester,
      find.widgetWithText(FilledButton, 'Add Location'),
    );
    // Let the "Photo captured successfully" snackbar dismiss so it no
    // longer overlays the bottom action bar.
    await tester.pump(const Duration(seconds: 5));

    await _tap(tester, find.widgetWithText(FilledButton, 'Add Location'));
    await _pumpUntil(tester, find.text('Connaught Place, New Delhi'));
    // Same again: wait out the "Location captured successfully" snackbar.
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);

    const description =
        'On-device end-to-end pothole near the metro crossing.';
    final descriptionField = find.byType(TextField);
    await _tap(tester, descriptionField);
    await tester.enterText(descriptionField, description);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));

    await _tap(tester, find.widgetWithText(FilledButton, 'Review & Submit'));
    await _pumpUntil(tester, find.widgetWithText(FilledButton, 'Submit Report'));

    await _tap(tester, find.widgetWithText(FilledButton, 'Submit Report'));
    // Real multipart POST -> Django; wait for the success screen.
    await _pumpUntil(
      tester,
      find.textContaining(RegExp(r'Report \S+ submitted')),
      timeout: const Duration(seconds: 90),
    );

    // ---- MY REPORTS ---------------------------------------------------------
    await _tap(tester, find.text('View My Reports'));
    await _pumpUntil(tester, find.text('My Reports'));
    await _pumpUntil(tester, find.text(description));

    // ---- ISSUE DETAILS ------------------------------------------------------
    await _tap(tester, find.text(description));
    await _pumpUntil(tester, find.text('Status timeline'));
    expect(find.text(description), findsOneWidget);
    expect(find.textContaining('Issue #'), findsOneWidget);
  });
}