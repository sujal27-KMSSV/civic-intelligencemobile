import 'package:civic_intelligence/core/theme/appearance_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppearanceController', () {
    test('starts in system mode', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final mode = await container.read(appearanceProvider.future);
      expect(mode, ThemeMode.system);
    });

    test('setMode updates the state and persists the choice', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container
          .read(appearanceProvider.notifier)
          .setMode(ThemeMode.dark);
      expect(container.read(appearanceProvider).valueOrNull, ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('appearance_mode'), 'dark');
    });

    test('restores a stored choice on the next launch', () async {
      SharedPreferences.setMockInitialValues({'appearance_mode': 'dark'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final mode = await container.read(appearanceProvider.future);
      expect(mode, ThemeMode.dark);
    });

    test('falls back to system when nothing was stored', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final mode = await container.read(appearanceProvider.future);
      expect(mode, ThemeMode.system);
    });
  });
}