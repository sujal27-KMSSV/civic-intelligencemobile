import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show File, HandshakeException, HttpException, IOException, SocketException;
import 'dart:isolate';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../models/issue.dart';
import '../constants/api_constants.dart';
import '../errors/app_exception.dart';
import '../utils/perf.dart';
import 'auth_storage.dart';

/// Responses below this many bytes are parsed on the calling isolate; larger
/// feeds (e.g. the full issue list) are decoded in a background isolate.
const int _isolateParseThreshold = 64 * 1024;

/// Standalone entry point for parsing an issue list off the UI isolate.
/// Returns the raw decoded JSON; validation happens in a final pass.
List<dynamic> _parseIssueListBytes(List<int> bytes) {
  return jsonDecode(utf8.decode(bytes)) as List<dynamic>;
}

/// Thin HTTP wrapper around the Django backend.
///
/// Owns request headers (auth token), JSON (de)serialisation, timeout and
/// network-error normalisation. Widgets must never talk to this directly;
/// they use repositories instead.
class ApiClient {
  final http.Client _client;
  final Duration _timeout;
  final AuthStorage _authStorage;

  /// Cold-start budget given to every safe-to-retry request (reads, auth and
  /// idempotent submissions). Render's free containers sleep after ~15 minutes
  /// of idle traffic and take ~30-60s to boot again, so the FIRST attempt must
  /// already be able to wait out that boot — a short first attempt would time
  /// out before the container answers and then waste the retry on the same
  /// boot. Visibly longer than [ApiClient._timeout] on purpose.
  static const Duration _coldStartTimeout = Duration(seconds: 60);

  /// Called when the server responds with HTTP 401.
  /// Injected by the auth layer to trigger automatic logout.
  void Function()? onUnauthorized;

  ApiClient({
    http.Client? client,
    Duration timeout = const Duration(seconds: 20),
    AuthStorage? authStorage,
  })  : _client = client ?? http.Client(),
        _timeout = timeout,
        _authStorage = authStorage ?? const SecureAuthStorage();

  Future<Map<String, String>> _getHeaders() async {
    final token = await _authStorage.readToken();
    final scheme = await _authStorage.readTokenScheme() ?? 'Token';

    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': '$scheme $token',
    };
  }

  Uri _buildUri(String path) => Uri.parse('${ApiConstants.baseUrl}$path');

  Future<Map<String, dynamic>> get(String path) async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      final result = await _guardWithRetry(
        () => _client.get(_buildUri(path), headers: headers),
        _handleResponse,
        method: 'GET',
        path: path,
        stopwatch: stopwatch,
      );
      ok = true;
      return result;
    } finally {
      perfLog('api', 'GET $path', stopwatch.elapsedMilliseconds);
      debugNet('GET', path, ok: ok, elapsedMs: stopwatch.elapsedMilliseconds);
    }
  }

  /// Auth-only POST (login/register). Routing it through [_guardWithRetry] is
  /// safe: a retried register lands as "user already exists" at worst (the
  /// first attempt succeeded), and a retried login just issues another token.
  /// This keeps a Render cold start (~50s first boot) from failing the very
  /// first Sign In of the day.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      final result = await _guardWithRetry(
        () => _client.post(
          _buildUri(path),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        ),
        (response) {
          _debugLogAuthShape(path, response);
          return _handleResponse(response);
        },
        method: 'POST',
        path: path,
        stopwatch: stopwatch,
      );
      ok = true;
      return result;
    } finally {
      perfLog('api', 'POST $path', stopwatch.elapsedMilliseconds);
      debugNet('POST', path, ok: ok, elapsedMs: stopwatch.elapsedMilliseconds);
    }
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      // A patch carries absolute replacement values (e.g. description), so a
      // retried request produces the same result — safe to recover from a
      // dropped connection without the user noticing.
      final result = await _guardWithRetry(
        () => _client.patch(
          _buildUri(path),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        ),
        _handleResponse,
        method: 'PATCH',
        path: path,
        stopwatch: stopwatch,
      );
      ok = true;
      return result;
    } finally {
      perfLog('api', 'PATCH $path', stopwatch.elapsedMilliseconds);
      debugNet('PATCH', path, ok: ok, elapsedMs: stopwatch.elapsedMilliseconds);
    }
  }

  Future<Map<String, dynamic>> multipartPost(
    String path, {
    required Map<String, String> fields,
    required List<MultipartFileData> files,
    Duration? timeout,
    Duration retryTimeout = const Duration(seconds: 60),
  }) async {
    final token = await _authStorage.readToken();
    final scheme = await _authStorage.readTokenScheme() ?? 'Token';
    final uri = _buildUri(path);

    // Sends a freshly-built request. A MultiPartRequest is finalized (streamed,
    // file re-read) on client.send and cannot be re-issued, so the retry path
    // must rebuild it — this also re-reads the photo from disk, which is fine.
    Future<http.Response> send() async {
      final request = http.MultipartRequest('POST', uri);
      request.headers['Accept'] = 'application/json';
      if (token != null) request.headers['Authorization'] = '$scheme $token';
      request.fields.addAll(fields);

      for (final file in files) {
        request.files.add(
          file.contentType == null
              ? await http.MultipartFile.fromPath(file.field, file.filePath)
              : await http.MultipartFile.fromPath(
                  file.field,
                  file.filePath,
                  contentType: file.contentType,
                ),
        );
      }

      final streamed = await _client.send(request);
      return http.Response.fromStream(streamed);
    }

    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      // Submitted through [_guardWithRetry]: the report submission always
      // carries a stable `client_request_id`, and the backend de-duplicates on
      // it, so a dropped connection / cold-server retry cannot create a
      // duplicate report. The retry runs with a shorter budget than the first
      // attempt so a genuinely dead network fails within ~2 minutes instead of
      // hanging the "Still working…" spinner indefinitely.
      final result = await _guardWithRetry(
        send,
        _handleResponse,
        method: 'multipart POST',
        path: path,
        stopwatch: stopwatch,
        timeout: timeout,
        retryTimeout: retryTimeout,
      );
      ok = true;
      return result;
    } finally {
      perfLog('api', 'multipart POST $path', stopwatch.elapsedMilliseconds);
      debugNet(
        'multipart POST',
        path,
        ok: ok,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Submits a report photo and coordinates:
  /// `POST /api/issues/` as `multipart/form-data`.
  ///
  /// Uses a longer timeout than ordinary requests: the backend uploads the
  /// photo and runs duplicate detection + rule-based civic analysis all within
  /// this single synchronous request.
  Future<Issue> submitIssue({
    required File image,
    required double latitude,
    required double longitude,
    String? description,
    String? category,
    String? imageSource,
    String? clientRequestId,
    Duration timeout = const Duration(seconds: 120),
    Duration retryTimeout = const Duration(seconds: 60),
  }) async {
    final fields = <String, String>{
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      if (category != null && category.trim().isNotEmpty)
        'category': category.trim(),
      if (imageSource != null && imageSource.trim().isNotEmpty)
        'image_source': imageSource.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (clientRequestId != null && clientRequestId.trim().isNotEmpty)
        'client_request_id': clientRequestId.trim(),
    };
    final json = await multipartPost(
      ApiConstants.issues,
      fields: fields,
      files: [
        MultipartFileData(
          field: 'image',
          filePath: image.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      ],
      timeout: timeout,
      retryTimeout: retryTimeout,
    );
    return Issue.fromSubmissionJson(json, description: description);
  }

  /// Fetches the current user's reports: `GET /api/my-reports/`.
  Future<List<Issue>> fetchMyReports() async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      final list = await _guardWithRetry(
        () => _client.get(_buildUri(ApiConstants.myReports), headers: headers),
        _handleIssueList,
        method: 'GET',
        path: ApiConstants.myReports,
        stopwatch: stopwatch,
      );
      ok = true;
      return list;
    } finally {
      perfLog('api', 'GET ${ApiConstants.myReports}', stopwatch.elapsedMilliseconds);
      debugNet(
        'GET',
        ApiConstants.myReports,
        ok: ok,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Fetches civic issues for the map: `GET /api/issues/`.
  Future<List<Issue>> fetchIssues() async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      final list = await _guardWithRetry(
        () => _client.get(_buildUri(ApiConstants.issues), headers: headers),
        _handleIssueList,
        method: 'GET',
        path: ApiConstants.issues,
        stopwatch: stopwatch,
      );
      ok = true;
      return list;
    } finally {
      perfLog('api', 'GET ${ApiConstants.issues}', stopwatch.elapsedMilliseconds);
      debugNet(
        'GET',
        ApiConstants.issues,
        ok: ok,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Fetches a single issue: `GET /api/issues/{id}/`.
  Future<Issue> fetchIssue(String id) async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      final json = await _guardWithRetry(
        () => _client.get(_buildUri(ApiConstants.issueById(id)), headers: headers),
        _handleResponse,
        method: 'GET',
        path: ApiConstants.issueById(id),
        stopwatch: stopwatch,
      );
      ok = true;
      return Issue.fromListJson(json);
    } finally {
      perfLog('api', 'GET ${ApiConstants.issueById(id)}', stopwatch.elapsedMilliseconds);
      debugNet(
        'GET',
        ApiConstants.issueById(id),
        ok: ok,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Deletes a submitted report: `DELETE /api/issues/{id}/`.
  ///
  /// The backend owns the rules: deletes outside the 10-minute retraction
  /// window (and deletes of other users' reports) come back as HTTP 403 and
  /// surface as [ServerException].
  Future<void> deleteIssue(String id) async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    var ok = false;
    try {
      await _guard(
        () => _client.delete(
          _buildUri(ApiConstants.issueById(id)),
          headers: headers,
        ),
        _handleResponse,
      );
      ok = true;
    } finally {
      perfLog(
        'api',
        'DELETE ${ApiConstants.issueById(id)}',
        stopwatch.elapsedMilliseconds,
      );
      debugNet(
        'DELETE',
        ApiConstants.issueById(id),
        ok: ok,
        elapsedMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// Decodes and maps a list response into [Issue]s, offloading the work to a
  /// background isolate when the payload is large so the UI thread stays
  /// responsive while parsing big feeds.
  List<Issue> _mapIssueList(List<dynamic> list) {
    return list.map((item) {
      if (item is! Map) {
        throw const ServerException(
          message: 'The server returned an unexpected response.',
        );
      }
      return Issue.fromListJson(item.cast<String, dynamic>());
    }).toList();
  }

  Future<List<Issue>> _handleIssueList(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final bytes = response.bodyBytes;
      final parse = bytes.length > _isolateParseThreshold
          ? _isolateParse(bytes)
          : _parseListBytes(bytes);
      return parse;
    }
    _throwForStatus(response.statusCode, _decodeBody(response));
  }

  Future<List<Issue>> _isolateParse(List<int> bytes) async {
    try {
      return _mapIssueList(await Isolate.run(() => _parseIssueListBytes(bytes)));
    } on RemoteError {
      throw const ServerException(
        message: 'The server returned an unexpected response.',
      );
    }
  }

  Future<List<Issue>> _parseListBytes(List<int> bytes) async {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const ServerException(
        message: 'The server returned an unexpected response.',
      );
    }
    if (decoded is! List<dynamic>) {
      throw const ServerException(
        message: 'The server returned an unexpected response.',
      );
    }
    return _mapIssueList(decoded);
  }

  /// Runs a request, applying the timeout and normalising transport errors
  /// into [NetworkException]s with a classified [NetworkErrorKind] so the UI
  /// can show a specific message instead of one generic "check your
  /// connection" line.
  Future<T> _guard<T>(
    Future<http.Response> Function() request,
    FutureOr<T> Function(http.Response) handle, {
    Duration? timeout,
  }) async {
    try {
      final response = await request().timeout(timeout ?? _timeout);
      return await handle(response);
    } on TimeoutException {
      throw const NetworkException(
        message: 'The server took too long to respond. It may still be '
            'starting up — please try again.',
        kind: NetworkErrorKind.timeout,
        isRetryable: true,
      );
    } on SocketException catch (e) {
      if (e.message.isEmpty) {
        throw const NetworkException(
          message: 'Could not reach the server.',
          kind: NetworkErrorKind.other,
          isRetryable: true,
        );
      }
      final msg = e.message.toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('name or service not known') ||
          msg.contains('getaddrinfo')) {
        throw const NetworkException(
          message: 'Could not reach the server. Check your internet '
              'connection.',
          kind: NetworkErrorKind.dns,
          isRetryable: true,
        );
      }
      if (msg.contains('refused')) {
        throw const NetworkException(
          message: 'The server is not responding right now. Try again shortly.',
          kind: NetworkErrorKind.connectionRefused,
        );
      }
      if (msg.contains('network is unreachable') ||
          msg.contains('no route to host')) {
        throw const NetworkException(
          message: 'You do not seem to be online. Check your connection.',
          kind: NetworkErrorKind.noInternet,
        );
      }
      throw const NetworkException(
        message: 'Could not reach the server. Check your connection.',
        kind: NetworkErrorKind.other,
        isRetryable: true,
      );
    } on http.ClientException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('connection closed') ||
          msg.contains('connection reset') ||
          msg.contains('connection aborted')) {
        throw const NetworkException(
          message: 'The connection dropped. Please try again.',
          kind: NetworkErrorKind.connectionReset,
          isRetryable: true,
        );
      }
      throw const NetworkException(
        message: 'Could not reach the server. Check your connection.',
        kind: NetworkErrorKind.other,
        isRetryable: true,
      );
    } on HandshakeException {
      throw const NetworkException(
        message:
            'Secure connection failed. Check your network or try again later.',
        kind: NetworkErrorKind.tls,
      );
    } on HttpException {
      throw const NetworkException(
        message: 'Could not reach the server. Check your connection.',
        kind: NetworkErrorKind.other,
        isRetryable: true,
      );
    } on IOException {
      throw const NetworkException(
        message: 'A connection error occurred. Please try again.',
        kind: NetworkErrorKind.other,
        isRetryable: true,
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw const NetworkException(
        message: 'A connection error occurred. Please try again.',
        kind: NetworkErrorKind.other,
      );
    }
  }

  /// Like [_guard] but retries the request ONCE after a short backoff when the
  /// failure is a safe-to-retry transport error.
  ///
  /// Used only for idempotent writes (login, register, multipart submit with a
  /// `client_request_id`) and reads (GET): re-issuing those is always safe.
  /// Both the first attempt and the retry run with the [retryTimeout] (or
  /// [_coldStartTimeout]) budget so a cold backend container (e.g. Render first
  /// boot, ~30-60s) can answer without the user seeing an error.
  Future<T> _guardWithRetry<T>(
    Future<http.Response> Function() request,
    FutureOr<T> Function(http.Response) handle, {
    required String method,
    required String path,
    required Stopwatch stopwatch,
    Duration? timeout,
    Duration? retryTimeout,
  }) async {
    // The first attempt also gets the cold-start budget: the server may be
    // booting (Render free sleeps when idle) and would otherwise time out at
    // [_timeout] before it answers, leaving the single retry to absorb the
    // whole cold start.
    final firstTimeout = timeout ?? _coldStartTimeout;
    try {
      return await _guard(request, handle, timeout: firstTimeout);
    } on NetworkException catch (e) {
      if (!e.isRetryable) rethrow;
      debugNet(
        method,
        path,
        ok: false,
        elapsedMs: stopwatch.elapsedMilliseconds,
        detail: '${e.kindName}; retrying once',
      );
      try {
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        return await _guard(
          request,
          handle,
          timeout: retryTimeout ?? firstTimeout,
        );
      } on NetworkException {
        debugNet(
          method,
          path,
          ok: false,
          elapsedMs: stopwatch.elapsedMilliseconds,
          detail: 'retry failed',
        );
        rethrow;
      }
    }
  }

  /// Optional transport diagnostics, compiled in with
  /// `--dart-define=DEBUG_NET=true`. Logs only endpoint, method, status,
  /// timings and error kinds — never request bodies, response bodies or
  /// credentials.
  void debugNet(
    String method,
    String path, {
    required bool ok,
    required int elapsedMs,
    String? detail,
  }) {
    if (!ApiConstants.debugNet) return;
    final safePath = path.split('?').first;
    debugPrint(
      '[net] $method $safePath ok=$ok ${elapsedMs}ms'
      '${detail == null ? '' : ' detail=$detail'}',
    );
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final decoded = _decodeBody(response);
    final statusCode = response.statusCode;

    if (statusCode >= 200 && statusCode < 300) {
      if (decoded != null && decoded is! Map<String, dynamic>) {
        throw const ServerException(
          message: 'The server returned an unexpected response.',
        );
      }
      return (decoded as Map<String, dynamic>?) ?? const {};
    }

    _throwForStatus(statusCode, decoded);
  }

  /// Diagnostics for the auth contract. Built with
  /// `--dart-define=DEBUG_AUTH=true`, logs the HTTP status and the top-level
  /// KEY NAMES of the auth response body so a contract mismatch is visible.
  /// Credential values (tokens, passwords) are never logged.
  void _debugLogAuthShape(String path, http.Response response) {
    if (!ApiConstants.debugAuth || !path.contains('/auth/')) return;

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }

    if (decoded is Map) {
      final map = decoded.cast<dynamic, dynamic>();
      debugPrint(
        '[auth] $path -> ${response.statusCode} '
        'keys=${map.keys.toList()} '
        'token=${map['token'] != null} '
        'key=${map['key'] != null} '
        'access=${map['access'] != null} '
        'refresh=${map['refresh'] != null} '
        'user=${map['user'] is Map}',
      );
    } else {
      debugPrint('[auth] $path -> ${response.statusCode} body=non-object');
    }
  }

  Object? _decodeBody(http.Response response) {
    try {
      return response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ServerException(
        message: 'The server returned an unexpected response.',
      );
    }
  }

  Never _throwForStatus(int statusCode, Object? decoded) {
    if (statusCode == 401) {
      onUnauthorized?.call();
      throw AuthException(
        message: 'Unauthorized. Please log in again.',
        statusCode: statusCode,
      );
    }

    if (statusCode == 404) {
      throw ServerException(
        message: 'Resource not found.',
        statusCode: statusCode,
      );
    }

    if ((statusCode == 400 || statusCode == 422) && decoded is Map<String, dynamic>) {
      final hasFieldErrors = decoded.values.any((v) => v is List);
      if (hasFieldErrors) {
        throw ValidationException(
          fieldErrors: decoded.map((k, v) => MapEntry(
            k.toString(),
            (v as List).map((e) => e.toString()).toList(),
          )),
          statusCode: statusCode,
        );
      }
      final detail = decoded['detail']?.toString() ?? decoded['error']?.toString();
      if (detail != null) {
        throw ServerException(message: detail, statusCode: statusCode);
      }
    }

    final errorMessage = decoded is Map<String, dynamic>
        ? decoded['detail']?.toString() ??
            decoded['error']?.toString() ??
            'An unexpected error occurred'
        : 'The server responded with an error (HTTP $statusCode).';
    throw ServerException(message: errorMessage, statusCode: statusCode);
  }
}

class MultipartFileData {
  final String field;
  final String filePath;
  final MediaType? contentType;

  const MultipartFileData({
    required this.field,
    required this.filePath,
    this.contentType,
  });
}