import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../errors/app_exception.dart';

/// Persists the authenticated session.
///
/// Kept as a thin interface so tests can inject an in-memory fake instead of
/// hitting the platform secure-storage channel.
abstract class AuthStorage {
  Future<String?> readToken();
  Future<String?> readTokenScheme();
  Future<String?> readUserId();
  Future<String?> readUserEmail();

  Future<void> saveSession({
    required String token,
    String? tokenScheme,
    String? refreshToken,
    String? userId,
    String? email,
  });

  Future<void> clear();
}

/// Production implementation backed by the OS keystore/Keychain.
///
/// Secure-storage reads are deliberately defensive: on platforms where the
/// keystore is momentarily unavailable (e.g. right after an OS/keychain reset,
/// background eviction, or a locked keychain), the app treats the value as
/// absent (signed-out) instead of crashing the auth flow with a raw
/// `PlatformException`. Writes surface a normalised error so login/register
/// can explain that the session could not be persisted.
class SecureAuthStorage implements AuthStorage {
  final FlutterSecureStorage _storage;

  const SecureAuthStorage([this._storage = const FlutterSecureStorage()]);

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      debugPrint('[auth-storage] read failed for "$key"; treating as absent');
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } on PlatformException {
      throw const AuthStorageException(
        message: 'Could not save your session securely. Please sign in again.',
      );
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      // Deleting a stale/nonexistent key is best-effort; ignore failures.
    } on MissingPluginException {
      // Ignore when the platform channel is unavailable (e.g. unit tests).
    }
  }

  @override
  Future<String?> readToken() => _read(AppConstants.tokenKey);

  @override
  Future<String?> readTokenScheme() => _read(AppConstants.tokenSchemeKey);

  @override
  Future<String?> readUserId() => _read(AppConstants.userIdKey);

  @override
  Future<String?> readUserEmail() => _read(AppConstants.emailKey);

  @override
  Future<void> saveSession({
    required String token,
    String? tokenScheme,
    String? refreshToken,
    String? userId,
    String? email,
  }) async {
    await _write(AppConstants.tokenKey, token);
    if (tokenScheme != null) {
      await _write(AppConstants.tokenSchemeKey, tokenScheme);
    }
    if (refreshToken != null) {
      await _write(AppConstants.refreshTokenKey, refreshToken);
    }
    if (userId != null) {
      await _write(AppConstants.userIdKey, userId);
    }
    if (email != null) {
      await _write(AppConstants.emailKey, email);
    }
  }

  @override
  Future<void> clear() async {
    await _delete(AppConstants.tokenKey);
    await _delete(AppConstants.tokenSchemeKey);
    await _delete(AppConstants.refreshTokenKey);
    await _delete(AppConstants.userIdKey);
    await _delete(AppConstants.emailKey);
  }
}

/// Thrown when the OS keychain refuses to persist a session.
class AuthStorageException extends AppException {
  const AuthStorageException({
    required super.message,
    super.statusCode,
  });

  @override
  String toString() => 'AuthStorageException: $message';
}
