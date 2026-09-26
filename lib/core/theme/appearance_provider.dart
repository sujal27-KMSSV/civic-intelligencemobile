import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the app's appearance choice (system/light/dark) between launches.
///
/// The default is `system`, so the device's own setting drives the theme until
/// the user picks something explicitly. The choice is saved with
/// `shared_preferences` and restored on the next start. When persistence is
/// unavailable (e.g. a platform that cannot reach shared_preferences) the
/// controller degrades to the system default instead of failing.
class AppearanceController extends AsyncNotifier<ThemeMode> {
  static const String _prefsKey = 'appearance_mode';

  @override
  Future<ThemeMode> build() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _modeFromStored(prefs.getString(_prefsKey));
    } catch (_) {
      return ThemeMode.system;
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _valueFor(mode));
    } catch (_) {
      // Persisting is best-effort; the in-memory mode is still applied below.
    }
    state = AsyncData(mode);
  }

  static String _valueFor(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
      };

  static ThemeMode _modeFromStored(String? value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// The single source of truth for the app's theme mode. Consumers should use
/// `valueOrNull ?? ThemeMode.system` so a still-loading or unavailable
/// preference falls back to following the device.
final appearanceProvider = AsyncNotifierProvider<AppearanceController, ThemeMode>(
  AppearanceController.new,
);