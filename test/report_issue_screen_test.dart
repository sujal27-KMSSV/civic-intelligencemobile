import 'package:civic_intelligence/features/reporting/report_draft_provider.dart';
import 'package:civic_intelligence/features/reporting/report_issue_screen.dart';
import 'package:civic_intelligence/services/location_service.dart';
import 'package:civic_intelligence/services/media_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_utils.dart';

Widget _buildApp(FakeMediaService service, {FakeLocationService? location}) {
  return ProviderScope(
    overrides: [
      mediaServiceProvider.overrideWithValue(service),
      if (location != null) locationServiceProvider.overrideWithValue(location),
    ],
    child: const MaterialApp(home: ReportIssueScreen()),
  );
}

void main() {
  testWidgets('shows category + photo actions, primary disabled first',
      (tester) async {
    final service = FakeMediaService();
    await tester.pumpWidget(_buildApp(service));

    expect(find.text('What did you find?'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('Open Camera'), findsOneWidget);
    expect(find.text('From Gallery'), findsOneWidget);
    expect(find.text('Step 2 of 3'), findsOneWidget);

    final primary = tester.widget<FilledButton>(
      find.byType(FilledButton).last,
    );
    expect(primary.onPressed, isNull);
  });

  testWidgets('selecting category enables photo capture, then success shows '
      'preview and can retake', (tester) async {
    final file = photoFile();
    final service = FakeMediaService(results: [
      MediaPickResult.success(file),
      MediaPickResult.success(file),
    ]);
    await tester.pumpWidget(_buildApp(service));

    await tester.tap(find.text('Pothole'));
    await tester.pump();

    expect(find.text('Pothole selected'), findsOneWidget);
    expect(find.text('Take a Photo'), findsOneWidget);

    final enabled = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(enabled.onPressed, isNotNull);

    await tester.tap(find.text('Take a Photo'));
    await tester.pumpAndSettle();

    expect(service.captureCalls, 1);
    expect(find.text('Retake'), findsOneWidget);
    expect(find.text('Add Location'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tapInList(tester, find.text('Retake'));

    expect(service.captureCalls, 2);
    expect(find.text('Retake'), findsOneWidget);
  });

  testWidgets('permission denial shows settings banner', (tester) async {
    final service = FakeMediaService(
      results: [MediaPickResult.permissionDenied()],
    );
    await tester.pumpWidget(_buildApp(service));

    final openCamera = find.text('Open Camera');
    await bringIntoView(tester, openCamera);
    await tester.tap(openCamera.first);
    await tester.pumpAndSettle();

    expect(service.captureCalls, 1);
    // The camera banner is inserted above the photo section, so scroll back up.
    await bringIntoView(tester, find.textContaining('Camera access is blocked'));
    expect(find.textContaining('Camera access is blocked'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('gallery pick succeeds', (tester) async {
    final file = photoFile();
    final service = FakeMediaService(results: [MediaPickResult.success(file)]);
    await tester.pumpWidget(_buildApp(service));

    await tester.tap(find.text('Pothole'));
    await tester.pump();
    await tapInList(tester, find.text('From Gallery'));

    expect(service.galleryCalls, 1);
    expect(find.text('Add Location'), findsOneWidget);
  });

  testWidgets('remove photo returns to placeholder', (tester) async {
    final file = photoFile();
    final service = FakeMediaService(results: [MediaPickResult.success(file)]);
    await tester.pumpWidget(_buildApp(service));

    await tester.tap(find.text('Pothole'));
    await tester.pump();
    await tapInList(tester, find.text('From Gallery'));
    expect(find.text('Add Location'), findsOneWidget);

    await tapInList(tester, find.text('Remove photo'));

    await bringIntoView(tester, find.text('No photo yet'));
    expect(find.text('No photo yet'), findsOneWidget);
    expect(find.text('Add Location'), findsNothing);
  });

  testWidgets('shows location placeholder and Get My Location initially',
      (tester) async {
    final service = FakeMediaService();
    final location = FakeLocationService();
    await tester.pumpWidget(_buildApp(service, location: location));

    await tapInList(tester, find.text('No location yet'));
    expect(find.text('Get My Location'), findsOneWidget);
  });

  testWidgets('location capture success shows address and coordinates',
      (tester) async {
    final service = FakeMediaService();
    final location = FakeLocationService(
      result: LocationResult.success(testLocation()),
    );
    await tester.pumpWidget(_buildApp(service, location: location));

    await tapInList(tester, find.text('Get My Location'));

    expect(location.calls, 1);
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);
    expect(find.textContaining('28.61390'), findsOneWidget);
    expect(find.textContaining('Accuracy ±12 m'), findsOneWidget);
    expect(find.text('Update'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets('location permission denial shows settings banner',
      (tester) async {
    final service = FakeMediaService();
    final location = FakeLocationService(
      result: LocationResult.permissionDenied(),
    );
    await tester.pumpWidget(_buildApp(service, location: location));

    await tapInList(tester, find.text('Get My Location'));

    expect(
      find.textContaining('Location permission is blocked'),
      findsOneWidget,
    );
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('location services off shows warning banner', (tester) async {
    final service = FakeMediaService();
    final location = FakeLocationService(
      result: LocationResult.serviceDisabled(),
    );
    await tester.pumpWidget(_buildApp(service, location: location));

    await tapInList(tester, find.text('Get My Location'));

    // The snackbar shows the same message, so assert via the banner button.
    expect(find.textContaining('Location services are turned off'), findsWidgets);
    expect(find.text('Open Location Settings'), findsOneWidget);
  });

  testWidgets('remove captured location returns to placeholder',
      (tester) async {
    final service = FakeMediaService();
    final location = FakeLocationService(
      result: LocationResult.success(testLocation()),
    );
    await tester.pumpWidget(_buildApp(service, location: location));

    await tapInList(tester, find.text('Get My Location'));
    expect(find.text('Connaught Place, New Delhi'), findsOneWidget);

    await tapInList(tester, find.text('Remove'));
    await bringIntoView(tester, find.text('No location yet'));
    expect(find.text('No location yet'), findsOneWidget);
  });

  testWidgets('primary button progresses Photo to Location to Submit',
      (tester) async {
    final file = photoFile();
    final service = FakeMediaService(results: [MediaPickResult.success(file)]);
    final location = FakeLocationService(
      result: LocationResult.success(testLocation()),
    );
    await tester.pumpWidget(_buildApp(service, location: location));

    await tester.tap(find.text('Pothole'));
    await tester.pump();
    await tapInList(tester, find.text('From Gallery'));
    await tester.pump();
    expect(find.text('Add Location'), findsOneWidget);

    // Let the "Photo captured" snackbar dismiss so it doesn't block the tap.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Location'));
    await tester.pumpAndSettle();

    expect(location.calls, 1);
    expect(find.text('Review & Submit'), findsOneWidget);
  });

  testWidgets('description field captures text with counter and stores in draft',
      (tester) async {
    final service = FakeMediaService();
    await tester.pumpWidget(_buildApp(service));

    final field = find.byType(TextField);
    await bringIntoView(tester, field);
    await tester.enterText(field.first, 'Pothole near the crossing.');
    await tester.pumpAndSettle();

    expect(find.text('26/500'), findsOneWidget);

    // Commit the draft by leaving the field (the screen only syncs on focus
    // loss / review, not per keystroke).
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    final container =
        ProviderScope.containerOf(tester.element(find.byType(ReportIssueScreen)));
    expect(container.read(reportDraftProvider).description,
        'Pothole near the crossing.');
  });
}