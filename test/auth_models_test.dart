import 'package:civic_intelligence/core/errors/app_exception.dart';
import 'package:civic_intelligence/features/auth/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginRequest', () {
    test('serialises to the Django field names', () {
      const request = LoginRequest(email: 'a@b.com', password: 'secret123');

      expect(request.toJson(), {
        'email': 'a@b.com',
        'password': 'secret123',
      });
    });
  });

  group('RegisterRequest', () {
    test('serialises with an optional phone number', () {
      const request = RegisterRequest(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'a@b.com',
        phone: '+911234567890',
        password: 'secret123',
      );

      expect(request.toJson(), {
        'first_name': 'Jane',
        'last_name': 'Doe',
        'email': 'a@b.com',
        'phone': '+911234567890',
        'password': 'secret123',
      });
    });

    test('omits a blank phone number', () {
      const request = RegisterRequest(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'a@b.com',
        phone: '   ',
        password: 'secret123',
      );

      expect(request.toJson().containsKey('phone'), isFalse);
    });

    test('omits a null phone number', () {
      const request = RegisterRequest(
        firstName: 'Jane',
        lastName: 'Doe',
        email: 'a@b.com',
        password: 'secret123',
      );

      expect(request.toJson().containsKey('phone'), isFalse);
    });
  });

  group('AuthResponse', () {
    test('parses a token-only response', () {
      final response = AuthResponse.fromJson({'token': 'abc123'});

      expect(response.token, 'abc123');
      expect(response.user, isNull);
    });

    test('parses a response with an embedded user', () {
      final response = AuthResponse.fromJson({
        'token': 'abc123',
        'user': {
          'id': 7,
          'email': 'a@b.com',
          'first_name': 'Jane',
          'last_name': 'Doe',
          'phone': '+911234567890',
        },
      });

      expect(response.token, 'abc123');
      expect(response.tokenScheme, 'Token');
      expect(response.user?.id, '7');
      expect(response.user?.email, 'a@b.com');
      expect(response.user?.fullName, 'Jane Doe');
    });

    test('accepts the DRF `key` response shape', () {
      final response = AuthResponse.fromJson({'key': 'abc123'});

      expect(response.token, 'abc123');
      expect(response.tokenScheme, 'Token');
    });

    test('accepts the SimpleJWT access/refresh response shape', () {
      final response = AuthResponse.fromJson({
        'access': 'jwt-access',
        'refresh': 'jwt-refresh',
        'user': {
          'id': 7,
          'email': 'a@b.com',
          'first_name': 'Jane',
          'last_name': 'Doe',
        },
      });

      expect(response.token, 'jwt-access');
      expect(response.tokenScheme, 'Bearer');
      expect(response.refreshToken, 'jwt-refresh');
      expect(response.user?.id, '7');
    });

    test('throws a clear AuthException when no token field is present', () {
      expect(
        () => AuthResponse.fromJson({'user': {'id': 7, 'email': 'a@b.com'}}),
        throwsA(isA<AuthException>()),
      );
    });
  });
}