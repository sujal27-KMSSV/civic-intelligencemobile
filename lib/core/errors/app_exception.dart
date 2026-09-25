class AppException implements Exception {
  final String message;
  final int? statusCode;

  const AppException({required this.message, this.statusCode});

  @override
  String toString() => 'AppException: $message (Status: $statusCode)';
}

/// Classifies a transport-level failure so the UI can show a specific,
/// helpful message instead of one generic "check your connection" line and so
/// the networking layer knows whether a retry is safe.
enum NetworkErrorKind {
  /// DNS resolution failed (no such host / no network route to it).
  dns,

  /// The host refused the connection (server not accepting connections).
  connectionRefused,

  /// No network / route unreachable (airplane mode, offline).
  noInternet,

  /// The server did not answer within the timeout (e.g. Render cold start).
  timeout,

  /// TLS handshake failed (certificate/network middlebox issues).
  tls,

  /// The connection was dropped/reset mid-request.
  connectionReset,

  /// Anything else at the transport layer.
  other,
}

class NetworkException extends AppException {
  const NetworkException({
    required super.message,
    super.statusCode,
    this.kind = NetworkErrorKind.other,
    this.isRetryable = false,
  });

  /// Why the request failed, for tailored UX and diagnostics.
  final NetworkErrorKind kind;

  /// True only when re-issuing the request is safe. Transport failures on
  /// idempotent requests (GET) qualify; writes are never auto-retried.
  final bool isRetryable;

  /// Name used when logging diagnostics. Never contains credentials.
  String get kindName => kind.name;
}

class AuthException extends AppException {
  const AuthException({required super.message, super.statusCode});
}

class ServerException extends AppException {
  const ServerException({required super.message, super.statusCode});
}

/// Thrown when the server rejects a request with field-level validation
/// errors (typically HTTP 400/422 from Django REST Framework).
class ValidationException extends AppException {
  /// Maps field names to the list of error messages reported by the server.
  final Map<String, List<String>> fieldErrors;

  const ValidationException({
    this.fieldErrors = const {},
    super.message = 'Validation failed',
    super.statusCode,
  });
}
