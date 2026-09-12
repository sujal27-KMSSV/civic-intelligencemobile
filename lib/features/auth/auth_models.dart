import '../../core/errors/app_exception.dart';
import '../../models/user.dart';

/// Request body for `POST /api/auth/login/`.
class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {
        'email': email,
        'password': password,
      };
}

/// Request body for `POST /api/auth/register/`.
class RegisterRequest {
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final String password;

  const RegisterRequest({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    required this.password,
  });

  Map<String, dynamic> toJson() => {
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone,
        'password': password,
      };
}

/// Parsed auth response from `POST /api/auth/login/` or
/// `POST /api/auth/register/`.
class AuthResponse {
  /// The credential sent in `Authorization` requests. For DRF token auth this
  /// is the raw token; for SimpleJWT it is the short-lived `access` token.
  final String token;

  /// HTTP scheme: `"Bearer"` for JSON Web Tokens, `"Token"` for DRF.
  final String tokenScheme;

  /// Optional long-lived JWT `refresh` token (kept for future refresh flows).
  final String? refreshToken;

  final User? user;

  const AuthResponse({
    required this.token,
    this.tokenScheme = 'Token',
    this.refreshToken,
    this.user,
  });

  /// Accepts the three standard Django auth response shapes:
  ///
  ///   DRF Token auth:  `{"token": "..."}`
  ///   DRF `key` style: `{"key": "..."}`
  ///   SimpleJWT:       `{"access": "...", "refresh": "..."}`
  ///
  /// All may embed a `user` object. Throws a clear [AuthException] instead of
  /// a raw cast error when the server returns none of the token fields, so the
  /// signup/login forms can show the real problem.
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['token'] ?? json['key'] ?? json['access'];
    if (raw is! String || raw.isEmpty) {
      throw const AuthException(
        message:
            'The server did not return a session token. Check the auth endpoint response format.',
      );
    }
    return AuthResponse(
      token: raw,
      tokenScheme: json['access'] is String ? 'Bearer' : 'Token',
      refreshToken: json['refresh'] is String ? json['refresh'] as String : null,
      user: json['user'] is Map<String, dynamic>
          ? User.fromJson(json['user'] as Map<String, dynamic>)
          : null,
    );
  }
}