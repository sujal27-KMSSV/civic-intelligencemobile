import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

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
class SecureAuthStorage implements AuthStorage {
  final FlutterSecureStorage _storage;

  const SecureAuthStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> readToken() =>
      _storage.read(key: AppConstants.tokenKey);

  @override
  Future<String?> readTokenScheme() =>
      _storage.read(key: AppConstants.tokenSchemeKey);

  @override
  Future<String?> readUserId() =>
      _storage.read(key: AppConstants.userIdKey);

  @override
  Future<String?> readUserEmail() =>
      _storage.read(key: AppConstants.emailKey);

  @override
  Future<void> saveSession({
    required String token,
    String? tokenScheme,
    String? refreshToken,
    String? userId,
    String? email,
  }) async {
    await _storage.write(key: AppConstants.tokenKey, value: token);
    if (tokenScheme != null) {
      await _storage.write(
        key: AppConstants.tokenSchemeKey,
        value: tokenScheme,
      );
    }
    if (refreshToken != null) {
      await _storage.write(
        key: AppConstants.refreshTokenKey,
        value: refreshToken,
      );
    }
    if (userId != null) {
      await _storage.write(key: AppConstants.userIdKey, value: userId);
    }
    if (email != null) {
      await _storage.write(key: AppConstants.emailKey, value: email);
    }
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: AppConstants.tokenKey);
    await _storage.delete(key: AppConstants.tokenSchemeKey);
    await _storage.delete(key: AppConstants.refreshTokenKey);
    await _storage.delete(key: AppConstants.userIdKey);
    await _storage.delete(key: AppConstants.emailKey);
  }
}