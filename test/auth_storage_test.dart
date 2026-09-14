import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/core/network/auth_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [FlutterSecureStorage] double whose reads can be forced to fail with a
/// [PlatformException] (simulating a locked/broken OS keychain).
class _ThrowingStorage extends FlutterSecureStorage {
  _ThrowingStorage({this.failReads = false, this.failWrites = false});

  final bool failReads;
  final bool failWrites;

  final Map<String, String> _data = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    if (failReads) {
      throw PlatformException(code: 'keychain_read_failed');
    }
    return _data[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    if (failWrites) {
      throw PlatformException(code: 'keychain_write_failed');
    }
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    MacOsOptions? mOptions,
  }) async {
    _data.remove(key);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureAuthStorage (testing storage failures)', () {
    test('failing reads fall back to null instead of crashing', () async {
      final storage = SecureAuthStorage(
        _ThrowingStorage(failReads: true),
      );

      expect(await storage.readToken(), isNull);
      expect(await storage.readTokenScheme(), isNull);
      expect(await storage.readUserId(), isNull);
      expect(await storage.readUserEmail(), isNull);
    });

    test('failing writes throw an AuthStorageException', () async {
      final storage = SecureAuthStorage(
        _ThrowingStorage(failWrites: true),
      );

      await expectLater(
        storage.saveSession(
          token: 'abc',
          userId: '1',
          email: 'a@b.com',
        ),
        throwsA(isA<AuthStorageException>()),
      );
    });

    test('successful save and read round-trips within a single instance',
        () async {
      final storage = SecureAuthStorage(_ThrowingStorage());
      await storage.saveSession(
        token: 'tok-1',
        tokenScheme: 'Token',
        userId: '42',
        email: 'a@b.com',
      );

      expect(await storage.readToken(), 'tok-1');
      expect(await storage.readTokenScheme(), 'Token');
      expect(await storage.readUserId(), '42');
      expect(await storage.readUserEmail(), 'a@b.com');
    });

    test('a read failure during restoreSession acts as signed-out', () async {
      final storage = SecureAuthStorage(
        _ThrowingStorage(failReads: true, failWrites: true),
      );

      // Simulate app startup: restoreSession() reads should not throw.
      expect(await storage.readToken(), isNull);
      expect(storage.readToken(), completes);
    });
  });

  group('AuthStorageException is an AppException', () {
    test('is catchable as an AppException', () {
      const err = AuthStorageException(message: 'boom');
      expect(err, isA<AppException>());
      expect(err.message, 'boom');
    });
  });
}
