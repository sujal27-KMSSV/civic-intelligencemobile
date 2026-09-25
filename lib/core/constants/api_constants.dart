class ApiConstants {
  ApiConstants._();

  /// The API base URL is a compile-time value, overridable for local
  /// development with `--dart-define=API_BASE_URL=...`.
  ///
  /// The DEFAULT is the production HTTPS backend so that ANY build that does
  /// not pass an explicit dart-define (including `flutter build apk --release`)
  /// targets production. A bare release build must never silently fall back to
  /// a development-only localhost/LAN URL.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://civic-intelligence-api.onrender.com',
  );

  static const String apiPrefix = '/api';

  // Auth
  static const String login = '$apiPrefix/auth/login/';
  static const String register = '$apiPrefix/auth/register/';

  // Issues
  static const String issues = '$apiPrefix/issues/';
  static String issueById(String id) => '$apiPrefix/issues/$id/';
  static const String myReports = '$apiPrefix/my-reports/';

  /// When true (build with `--dart-define=DEBUG_AUTH=true`), ApiClient logs the
  /// status code and top-level key names of auth responses. It NEVER logs
  /// tokens, refresh tokens or other credential values.
  static const bool debugAuth = bool.fromEnvironment('DEBUG_AUTH');

  /// When true (build with `--dart-define=DEBUG_NET=true`), ApiClient logs
  /// endpoint, method, outcome, timings and retry detail for every request.
  /// It NEVER logs request/response bodies or credentials.
  static const bool debugNet = bool.fromEnvironment('DEBUG_NET');
}
