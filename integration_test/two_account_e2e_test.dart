import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_helpers.dart';

void _step(String s) => debugPrint('[E2E-PROGRESS] $s');

/// On-device, real-production two-account smoke test.
///
/// Account A is the long-lived demo account (4 legacy reports). Account B is a
/// freshly registered citizen. The test proves account isolation (B never sees
/// A's reports and vice versa), the full camera/gallery report pipeline, edit
/// and delete (both gated on `can_edit` / `can_delete`), and that data
/// survives session switching.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'two-account flow: A report/edit/delete then B isolation, report, switch',
    (tester) async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final bEmail = 'duoe2eB$ts@example.com';
      const bPassword = 'Strong!Password9';

      final aDescription = 'A-E2E-$ts pothole outside the metro crossing.';
      final aEdited = '$aDescription EDITED-BY-E2E';
      final bDescription = 'B-E2E-$ts overflowing garbage bins near market.';
      final bEdited = '$bDescription EDITED-BY-E2E';

      final photo = await writeValidPhoto();
      expect(File(photo.path).existsSync(), isTrue);
      expect(photo.lengthSync(), greaterThan(0));

      // ---- A: clean start + login -----------------------------------------
      _step('reset + pump');
      await resetSession(tester);
      await pumpApp(tester, photo: photo);

      _step('A login');
      await login(tester, email: accountAEmail, password: accountAPassword);

      // Baseline: 4 legacy reports, none deletable (all are far outside the
      // 10-minute delete window; only recent reports get a Delete button).
      _step('A my-reports baseline');
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await pumpUntil(tester, find.text('4 reports'));
      expect(find.text('Delete'), findsNothing);

      // ---- A: create a camera report --------------------------------------
      _step('A create camera report');
      await tapWidget(tester, find.text('Home'));
      await pumpUntil(tester, find.text('Community Reports'));
      await createReport(
        tester,
        category: 'Pothole',
        description: aDescription,
        photoButton: 'Open Camera',
      );

      _step('A my-reports has 5');
      await openMyReportsWith(tester, aDescription);
      await pumpUntil(tester, find.text('5 reports'));

      // A quick detail nav and back.
      _step('A detail/back');
      await tapWidget(tester, find.text(aDescription));
      await pumpUntil(tester, find.text('Status timeline'));
      await tester.pageBack();
      await pumpUntil(tester, find.text('5 reports'));

      // ---- A: edit own report (can_edit gate) -----------------------------
      _step('A edit report');
      await editEditableReport(tester, newDescription: aEdited);
      await pumpUntil(tester, find.text(aEdited));
      await pumpUntil(tester, find.text('5 reports'));

      // ---- A: delete own report (can_delete gate, 10-min window) ----------
      _step('A delete report');
      await deleteEditableReport(tester);
      await waitForReportsText(tester, '4 reports');
      expect(find.text(aEdited), findsNothing);

      // ---- A: logout -------------------------------------------------------
      _step('A logout');
      await logout(tester);

      // ---- B: fresh account, sees nothing from A ---------------------------
      _step('B register');
      await register(tester, email: bEmail, password: bPassword);

      _step('B my-reports empty');
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await waitForReportsText(tester, 'No reports yet');
      expect(find.text(aEdited), findsNothing);

      // ---- B: create a gallery report --------------------------------------
      _step('B create gallery report');
      await tapWidget(tester, find.text('Home'));
      await pumpUntil(tester, find.text('Community Reports'));
      await createReport(
        tester,
        category: 'Garbage & Waste',
        description: bDescription,
        photoButton: 'From Gallery',
      );

      _step('B my-reports has 1');
      await openMyReportsWith(tester, bDescription);
      await waitForReportsText(tester, '1 report');

      // ---- B: edit own report ----------------------------------------------
      _step('B edit report');
      await editEditableReport(tester, newDescription: bEdited);
      await pumpUntil(tester, find.text(bEdited));
      await waitForReportsText(tester, '1 report');

      // ---- B: logout, back to A --------------------------------------------
      _step('B logout');
      await logout(tester);

      _step('A login again');
      await login(tester, email: accountAEmail, password: accountAPassword);
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await waitForReportsText(tester, '4 reports');
      expect(find.text(bDescription), findsNothing);
      expect(find.text(bEdited), findsNothing);

      _step('A logout again');
      await logout(tester);

      // ---- B: back in, their edit survived the switch ----------------------
      _step('B login again');
      await login(tester, email: bEmail, password: bPassword);
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await waitForReportsText(tester, '1 report');
      await waitForReportsText(tester, bEdited);

      // ---- B: delete own report and land on the empty state ---------------
      _step('B delete report');
      await deleteEditableReport(tester);
      await waitForReportsText(tester, 'No reports yet');

      _step('B logout');
      await logout(tester);
      _step('DONE');
    },
    timeout: const Timeout(Duration(minutes: 20)),
  );
}