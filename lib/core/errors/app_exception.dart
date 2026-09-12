class AppException implements Exception {
  final String message;
  final int? statusCode;

  const AppException({required this.message, this.statusCode});

  @override
  String toString() => 'AppException: $message (Status: $statusCode)';
}

class NetworkException extends AppException {
  const NetworkException({required super.message, super.statusCode});
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
