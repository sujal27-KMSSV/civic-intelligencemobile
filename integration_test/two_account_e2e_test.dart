import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'e2e_helpers.dart';

void _step(String s) => debugPrint('[E2E-PROGRESS] $s');

/// On-device, real-production two-account smoke test.
///
/// Fully self-contained: BOTH accounts self-register fresh throwaway accounts
/// at runtime (no shared long-lived credentials anywhere in the suite) and end
/// the run with zero reports (self-cleaning). The test proves:
///   * full camera + gallery report pipeline against the real backend,
///   * edit / delete gated by the server's `can_edit` / `can_delete`,
///   * report counters ("1 report", "2 reports") and the empty state,
///   * edits persist across logout / login and across account switches,
///   * account isolation in BOTH directions (A never sees B's reports and B
///     never sees A's reports).
///
/// My Reports renders newest-first, so with more than one editable report the
/// first `Edit` / `Delete` button in tree order belongs to the newest report.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'two-account self-contained flow: A report/edit/delete then B isolation',
    (tester) async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final aEmail = 'duoe2eA$ts@example.com';
      final bEmail = 'duoe2eB$ts@example.com';
      // TEST-ONLY throwaway fixtures for freshly registered accounts; never a
      // real user credential.
      const String aPassword = 'Strong!DuelA9z';
      const String bPassword = 'Strong!DuelB9z';

      final aR1 = 'A-E2E-$ts-1 pothole outside the metro crossing.';
      final aR2 = 'A-E2E-$ts-2 overflowing bins near the market.';
      final aEdited2 = '$aR2 EDITED-BY-E2E';
      final bR1 = 'B-E2E-$ts streetlight flickering near the bus stop.';
      final bEdited = '$bR1 EDITED-BY-E2E';

      final photo = await writeValidPhoto();
      expect(File(photo.path).existsSync(), isTrue);
      expect(photo.lengthSync(), greaterThan(0));

      // ---- A: fresh account, start clean -----------------------------------
      _step('reset + pump');
      await resetSession(tester);
      await pumpApp(tester, photo: photo);

      _step('A register');
      await register(tester, email: aEmail, password: aPassword);

      _step('A my-reports empty');
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await waitForReportsText(tester, 'No reports yet');

      // ---- A: create a camera report ----------------------------------------
      _step('A create camera report 1');
      await tapWidget(tester, find.text('Home'));
      await pumpUntil(tester, find.text('Community Reports'));
      await createReport(
        tester,
        category: 'Pothole',
        description: aR1,
        photoButton: 'Open Camera',
      );

      _step('A my-reports has 1');
      await openMyReportsWith(tester, aR1);
      await waitForReportsText(tester, '1 report');

      // ---- A: create a gallery report ---------------------------------------
      _step('A create gallery report 2');
      await tapWidget(tester, find.text('Home'));
      await pumpUntil(tester, find.text('Community Reports'));
      await createReport(
        tester,
        category: 'Garbage & Waste',
        description: aR2,
        photoButton: 'From Gallery',
      );

      _step('A my-reports has 2');
      await openMyReportsWith(tester, aR2);
      await waitForReportsText(tester, '2 reports');
      expect(find.text('Edit'), findsNWidgets(2));

      // ---- A: edit the newest report (can_edit gate) -----------------------
      _step('A edit newest report');
      await editEditableReport(tester, newDescription: aEdited2);
      await pumpUntil(tester, find.text(aEdited2));
      await waitForReportsText(tester, '2 reports');

      // ---- A: delete the newest report (can_delete gate) --------------------
      _step('A delete newest report');
      await deleteEditableReport(tester);
      await waitForReportsText(tester, '1 report');
      expect(find.text(aEdited2), findsNothing);

      // ---- A: delete the remaining report and land on the empty state -------
      _step('A delete only remaining report');
      await deleteEditableReport(tester);
      await waitForReportsText(tester, 'No reports yet');

      _step('A logout');
      await logout(tester);

      // ---- B: fresh account sees NOTHING from A -----------------------------
      _step('B register');
      await register(tester, email: bEmail, password: bPassword);

      _step('B my-reports empty (isolation)');
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await waitForReportsText(tester, 'No reports yet');
      expect(find.text(aR1), findsNothing);
      expect(find.text(aEdited2), findsNothing);
      expect(find.text('Edit'), findsNothing);

      // ---- B: create a camera report ----------------------------------------
      _step('B create camera report');
      await tapWidget(tester, find.text('Home'));
      await pumpUntil(tester, find.text('Community Reports'));
      await createReport(
        tester,
        category: 'Pothole',
        description: bR1,
        photoButton: 'Open Camera',
      );

      _step('B my-reports has 1');
      await openMyReportsWith(tester, bR1);
      await waitForReportsText(tester, '1 report');

      // ---- B: edit own report -----------------------------------------------
      _step('B edit report');
      await editEditableReport(tester, newDescription: bEdited);
      await pumpUntil(tester, find.text(bEdited));
      await waitForReportsText(tester, '1 report');

      // ---- B logout, back to A: A is still empty and untouched --------------
      _step('B logout');
      await logout(tester);

      _step('A login again');
      await login(tester, email: aEmail, password: aPassword);
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await waitForReportsText(tester, 'No reports yet');
      expect(find.text(bR1), findsNothing);
      expect(find.text(bEdited), findsNothing);

      _step('A logout again');
      await logout(tester);

      // ---- B: back in, their edit survived the switch -----------------------
      _step('B login again');
      await login(tester, email: bEmail, password: bPassword);
      await tapWidget(tester, find.text('Reports'));
      await pumpUntil(tester, find.text('My Reports'));
      await waitForReportsText(tester, '1 report');
      await waitForReportsText(tester, bEdited);

      // ---- B: delete own report and land on the empty state -----------------
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