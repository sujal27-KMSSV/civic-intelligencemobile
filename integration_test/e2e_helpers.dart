import 'dart:io';
import 'dart:ui' as ui;

import 'package:civic_intelligence/main.dart' as app;
import 'package:civic_intelligence/models/location_point.dart';
import 'package:civic_intelligence/services/location_service.dart';
import 'package:civic_intelligence/services/media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' show LocationAccuracy;
import 'package:path_provider/path_provider.dart';

const String kFakeAddress = 'Connaught Place, New Delhi';

/// Draws a 640x480 solid-colour frame and encodes it as a real PNG (>= the
/// backend's 320px minimum), so device-side E2E reports carry a genuinely
/// valid photo that the production image validator accepts. Written to the
/// app's temporary directory so MediaService consumers can read it.
Future<File> writeValidPhoto() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 640, 480),
    Paint()..color = const Color(0xFF2E7D32),
  );
  final image = await recorder.endRecording().toImage(640, 480);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final temp = await getTemporaryDirectory();
  final file = File(
    '${temp.path}/e2e_${DateTime.now().millisecondsSinceEpoch}.png',
  );
  await file.writeAsBytes(data!.buffer.asUint8List());
  return file;
}

class FakeMediaService extends MediaService {
  FakeMediaService(this.file);

  final File file;

  @override
  Future<MediaPickResult> capturePhoto() async =>
      MediaPickResult.success(file, source: 'camera');

  @override
  Future<MediaPickResult> pickFromGallery() async =>
      MediaPickResult.success(file, source: 'gallery');
}

class FakeLocationService extends LocationService {
  @override
  Future<LocationResult> captureCurrentLocation({
    LocationAccuracy accuracy = LocationAccuracy.high,
    bool resolveAddress = true,
  }) async {
    return LocationResult.success(LocationPoint(
      latitude: 28.6139,
      longitude: 77.2090,
      accuracy: 12,
      address: kFakeAddress,
      capturedAt: DateTime(2026, 1, 1, 10, 30),
    ));
  }
}

/// Pumps a fresh [app.FixMyGridApp] inside a [ProviderScope] with the fake
/// media/location services wired up. Extra provider overrides (for example a
/// flaky feed repository in the network-failure test) can be supplied.
Future<void> pumpApp(
  WidgetTester tester, {
  required File photo,
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mediaServiceProvider.overrideWithValue(FakeMediaService(photo)),
        locationServiceProvider.overrideWithValue(FakeLocationService()),
        ...overrides,
      ],
      child: const app.FixMyGridApp(),
    ),
  );
}

/// Pumps frames (real time on a device) until [finder] matches, or fails.
Future<void> pumpUntil(
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

/// Waits for [finder], scrolls it into view, then taps it.
Future<void> tapWidget(WidgetTester tester, Finder finder) async {
  await pumpUntil(tester, finder);
  await tester.ensureVisible(finder.first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(finder.first, warnIfMissed: false);
  await tester.pump(const Duration(milliseconds: 300));
}

/// Waits for the session storage to be cleared and the login screen to appear.
Future<void> resetSession(WidgetTester tester) async {
  const storage = FlutterSecureStorage();
  await storage.deleteAll();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 300));
}

/// Fills the login form and waits for the authenticated home shell.
Future<void> login(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await pumpUntil(tester, find.text('Sign In'));
  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), email);
  await tester.enterText(fields.at(1), password);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));
  await tapWidget(tester, find.text('Sign In'));
  // Production free-tier cold start can exceed 40s for the first auth call.
  await pumpUntil(
    tester,
    find.text('Community Reports'),
    timeout: const Duration(seconds: 120),
  );
  expect(find.byType(NavigationBar), findsWidgets);
}

/// Registers a brand-new citizen account and lands on the home shell.
Future<void> register(
  WidgetTester tester, {
  required String email,
  required String password,
}) async {
  await pumpUntil(tester, find.text('Sign In'));
  await tapWidget(tester, find.text('Create Account'));
  await pumpUntil(tester, find.text('Register'));

  final fields = find.byType(TextFormField);
  await tester.enterText(fields.at(0), 'E2E');
  await tester.enterText(fields.at(1), 'Flow');
  await tester.enterText(fields.at(2), email);
  await tester.enterText(fields.at(3), '+911234567890');
  await tester.enterText(fields.at(4), password);
  await tester.enterText(fields.at(5), password);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));

  await tapWidget(tester, find.text('Register'));
  await pumpUntil(
    tester,
    find.text('Community Reports'),
    timeout: const Duration(seconds: 120),
  );
  expect(find.byType(NavigationBar), findsWidgets);
}

/// Logs out from the Profile tab (confirms the dialog) and lands on Sign In.
Future<void> logout(WidgetTester tester) async {
  await tapWidget(tester, find.text('Profile'));
  await pumpUntil(tester, find.text('Logout'));

  await tapWidget(tester, find.text('Logout'));
  await pumpUntil(
    tester,
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Logout')),
  );
  await tapWidget(
    tester,
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Logout'),
    ).last,
  );
  await pumpUntil(tester, find.text('Sign In'));
  expect(find.byType(NavigationBar), findsNothing);
}

/// Waits for [text] on the My Reports screen. If a load error surfaces (rate
/// limit / transient backend hiccup) its `Retry` action is tapped so the wait
/// can continue, tolerating slow list refreshes of the shared production API.
Future<void> waitForReportsText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 120),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text(text).evaluate().isNotEmpty) return;
    final retry = find.widgetWithText(FilledButton, 'Retry');
    if (retry.evaluate().isNotEmpty) {
      await tester.tap(retry.first);
      await tester.pump();
    }
  }
  final visible = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .toSet()
      .toList()
    ..sort();
  debugPrint('[E2E-PROGRESS] timeout diagnostics, visible texts: $visible');
  fail('Timed out waiting for: $text');
}

/// Walks the full report flow and stops on the success screen (`Report #x
/// submitted`). [photoButton] picks the provenance control: `Open Camera` or
/// `From Gallery`.
Future<void> createReport(
  WidgetTester tester, {
  required String category,
  required String description,
  String photoButton = 'Open Camera',
}) async {
  await tapWidget(tester, find.text('Report'));
  await pumpUntil(tester, find.text('What did you find?'));
  expect(find.text('Report Issue'), findsOneWidget);

  await tapWidget(tester, find.text(category));

  await tapWidget(tester, find.text(photoButton));
  await pumpUntil(tester, find.widgetWithText(FilledButton, 'Add Location'));
  // Let the "Photo captured successfully" snackbar dismiss.
  await tester.pump(const Duration(seconds: 5));

  await tapWidget(tester, find.widgetWithText(FilledButton, 'Add Location'));
  await pumpUntil(tester, find.text(kFakeAddress));
  // Same again: wait out the "Location captured successfully" snackbar.
  await tester.pump(const Duration(seconds: 5));

  final descriptionField = find.byType(TextField);
  await tapWidget(tester, descriptionField);
  await tester.enterText(descriptionField, description);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));

  await tapWidget(tester, find.widgetWithText(FilledButton, 'Review & Submit'));
  await pumpUntil(tester, find.widgetWithText(FilledButton, 'Submit Report'));
  await tapWidget(tester, find.widgetWithText(FilledButton, 'Submit Report'));

  // Real multipart POST -> Django; wait for the success screen.
  await pumpUntil(
    tester,
    find.textContaining(RegExp(r'Report \S+ submitted')),
    timeout: const Duration(seconds: 90),
  );
}

/// Opens My Reports from the success screen and waits for [description] to
/// appear in the list.
Future<void> openMyReportsWith(
  WidgetTester tester,
  String description,
) async {
  await tapWidget(tester, find.text('View My Reports'));
  await pumpUntil(tester, find.text('My Reports'));
  await pumpUntil(tester, find.text(description));
}

/// Opens the edit dialog for the (single) editable report and rewrites its
/// description, waiting for the `Report updated.` confirmation snackbar.
Future<void> editEditableReport(
  WidgetTester tester, {
  required String newDescription,
}) async {
  await tapWidget(tester, find.text('Edit'));
  await pumpUntil(tester, find.text('Edit report'));

  final fields = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), newDescription);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump(const Duration(milliseconds: 500));

  await tapWidget(
    tester,
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')),
  );
  await pumpUntil(tester, find.text('Report updated.'));
  // Let the confirmation snackbar dismiss so it cannot swallow later taps.
  await tester.pump(const Duration(seconds: 5));
}

/// Deletes the (single) editable report via the confirmation dialog, waiting
/// for the `Report deleted.` snackbar.
Future<void> deleteEditableReport(WidgetTester tester) async {
  await tapWidget(tester, find.text('Delete'));
  await pumpUntil(tester, find.text('Delete this report?'));
  await tapWidget(
    tester,
    find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')),
  );
  await pumpUntil(tester, find.text('Report deleted.'));
  await tester.pump(const Duration(seconds: 5));
}