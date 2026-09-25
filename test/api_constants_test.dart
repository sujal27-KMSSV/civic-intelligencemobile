import 'package:civic_intelligence/core/constants/api_constants.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the compile-time footgun: a build that does NOT pass
/// `--dart-define=API_BASE_URL=...` (including a plain `flutter build apk
/// --release`) must target the production HTTPS backend, never a
/// localhost/LAN development URL.
void main() {
  test('bare builds default to the production HTTPS backend', () {
    expect(
      ApiConstants.baseUrl,
      'https://civic-intelligence-api.onrender.com',
    );
    expect(ApiConstants.baseUrl.startsWith('https://'), isTrue);
  });

  test('default base URL is never a development-only URL', () {
    expect(ApiConstants.baseUrl.contains('localhost'), isFalse);
    expect(ApiConstants.baseUrl.contains('10.0.2.2'), isFalse);
    expect(ApiConstants.baseUrl.contains('127.0.0.1'), isFalse);
    expect(ApiConstants.baseUrl.contains('192.168.'), isFalse);
  });
}
