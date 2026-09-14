import 'dart:convert';

import 'package:civic_intelligence/core/network/api_client.dart';
import 'package:civic_intelligence/features/auth/auth_state.dart';
import 'package:civic_intelligence/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'test_utils.dart';

void main() {
  testWidgets('Splash shows then navigates to login', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStorageProvider.overrideWithValue(InMemoryAuthStorage()),
        ],
        child: const FixMyGridApp(),
      ),
    );
    await tester.pump();

    expect(find.text('FixMyGrid'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets(
    'Failed login shows the server error and stays on the login screen',
    (WidgetTester tester) async {
      final storage = InMemoryAuthStorage();
      final api = ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'non_field_errors': ['Unable to log in with provided credentials.'],
              }),
              400,
              headers: {'content-type': 'application/json'},
            )),
        authStorage: storage,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStorageProvider.overrideWithValue(storage),
            apiClientProvider.overrideWithValue(api),
          ],
          child: const FixMyGridApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'wrong-password',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Sign In'));
      await tester.pump();
      await tester.pump();

      // Still on the login screen — not bounced away — with the backend error.
      expect(find.text('Sign In'), findsOneWidget);
      expect(
        find.text('Unable to log in with provided credentials.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Failed registration shows the server error on the register screen',
    (WidgetTester tester) async {
      final storage = InMemoryAuthStorage();
      final api = ApiClient(
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'email': ['A user with that email already exists.'],
              }),
              400,
              headers: {'content-type': 'application/json'},
            )),
        authStorage: storage,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStorageProvider.overrideWithValue(storage),
            apiClientProvider.overrideWithValue(api),
          ],
          child: const FixMyGridApp(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'First Name'),
        'Jane',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Last Name'),
        'Doe',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'taken@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'SafeCivic#123',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm Password'),
        'SafeCivic#123',
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Register'));
      await tester.pump();
      await tester.pump();

      // Still on the register screen — not stranded on the splash — with the
      // field error surfaced under the email input.
      expect(find.text('Register'), findsOneWidget);
      expect(
        find.text('A user with that email already exists.'),
        findsOneWidget,
      );
    },
  );
}