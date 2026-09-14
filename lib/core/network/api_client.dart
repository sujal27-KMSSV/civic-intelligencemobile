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
    try {
      return await _guard(
        () => _client.get(_buildUri(path), headers: headers),
        _handleResponse,
      );
    } finally {
      perfLog('api', 'GET $path', stopwatch.elapsedMilliseconds);
    }
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    try {
      return await _guard(
        () => _client.post(
          _buildUri(path),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        ),
        (response) {
          _debugLogAuthShape(path, response);
          return _handleResponse(response);
        },
      );
    } finally {
      perfLog('api', 'POST $path', stopwatch.elapsedMilliseconds);
    }
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    try {
      return await _guard(
        () => _client.patch(
          _buildUri(path),
          headers: headers,
          body: body != null ? jsonEncode(body) : null,
        ),
        _handleResponse,
      );
    } finally {
      perfLog('api', 'PATCH $path', stopwatch.elapsedMilliseconds);
    }
  }

  Future<Map<String, dynamic>> multipartPost(
    String path, {
    required Map<String, String> fields,
    required List<MultipartFileData> files,
    Duration? timeout,
  }) async {
    final token = await _authStorage.readToken();
    final scheme = await _authStorage.readTokenScheme() ?? 'Token';
    final uri = _buildUri(path);

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

    final stopwatch = Stopwatch()..start();
    try {
      return await _guard(
        () async {
          final streamed = await _client.send(request);
          return http.Response.fromStream(streamed);
        },
        _handleResponse,
        timeout: timeout,
      );
    } finally {
      perfLog('api', 'multipart POST $path', stopwatch.elapsedMilliseconds);
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
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final fields = <String, String>{
      'latitude': latitude.toString(),
      'longitude': longitude.toString(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
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
    );
    return Issue.fromSubmissionJson(json, description: description);
  }

  /// Fetches the current user's reports: `GET /api/my-reports/`.
  Future<List<Issue>> fetchMyReports() async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    try {
      final list = await _guard(
        () => _client.get(_buildUri(ApiConstants.myReports), headers: headers),
        _handleIssueList,
      );
      return list;
    } finally {
      perfLog('api', 'GET ${ApiConstants.myReports}', stopwatch.elapsedMilliseconds);
    }
  }

  /// Fetches civic issues for the map: `GET /api/issues/`.
  Future<List<Issue>> fetchIssues() async {
    final headers = await _getHeaders();
    final stopwatch = Stopwatch()..start();
    try {
      final list = await _guard(
        () => _client.get(_buildUri(ApiConstants.issues), headers: headers),
        _handleIssueList,
      );
      return list;
    } finally {
      perfLog('api', 'GET ${ApiConstants.issues}', stopwatch.elapsedMilliseconds);
    }
  }

  /// Fetches a single issue: `GET /api/issues/{id}/`.
  Future<Issue> fetchIssue(String id) async {
    final headers = await _getHeaders();
    final json = await _guard(
      () => _client.get(_buildUri(ApiConstants.issueById(id)), headers: headers),
      _handleResponse,
    );
    return Issue.fromListJson(json);
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
  /// into [NetworkException]s.
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
        message: 'The server took too long to respond. Please try again.',
      );
    } on http.ClientException {
      throw const NetworkException(
        message: 'Could not reach the server. Check your connection.',
      );
    } on SocketException {
      throw const NetworkException(
        message: 'Could not reach the server. Check your connection.',
      );
    } on HandshakeException {
      throw const NetworkException(
        message:
            'Secure connection failed. Check your network or try again later.',
      );
    } on HttpException {
      throw const NetworkException(
        message: 'Could not reach the server. Check your connection.',
      );
    } on IOException {
      throw const NetworkException(
        message: 'A connection error occurred. Please try again.',
      );
    } catch (e) {
      if (e is AppException) rethrow;
      throw const NetworkException(
        message: 'A connection error occurred. Please try again.',
      );
    }
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