class ApiConstants {
  ApiConstants._();

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
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
}
