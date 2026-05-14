import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../storage/session_storage.dart';
import 'api_config.dart';
import 'api_exception.dart';
import 'idempotency_store.dart';

/// Thin HTTP wrapper that adds:
/// - the configured base URL + standard headers,
/// - the `Authorization: Bearer ...` header when the call is protected,
/// - automatic refresh + single retry on a 401 (`TOKEN_EXPIRED`),
/// - parsing of the backend's error envelope (`00_README.md`),
/// - idempotency-key persistence — same UUID is reused across retries
///   of the same logical action until the server returns a terminal
///   response.
///
/// Auth model (per `endpoint_resources/00_README.md` + the integration
/// brief):
/// - **access_token** lives in-memory only on this client. On cold
///   start there is no access token; the first protected call drives
///   a refresh round-trip. Cleared on logout.
/// - **refresh_token** lives in `SessionStorage` (Keychain / encrypted
///   shared prefs). Single-use rotation: the new pair is persisted
///   before the request that consumed it returns. Concurrent 401s
///   share a single in-flight refresh so we never reuse a refresh
///   token (which would force-revoke the entire family).
class ApiClient {
  ApiClient({
    required SessionStorage storage,
    IdempotencyStore? idempotencyStore,
    http.Client? client,
  })  : _storage = storage,
        _idempotency = idempotencyStore ?? IdempotencyStore(),
        _client = client ?? http.Client();

  final SessionStorage _storage;
  final IdempotencyStore _idempotency;
  final http.Client _client;

  /// In-memory access token. Populated by [cacheAccessToken] (after
  /// OTP verify, profile setup) and by `_runRefresh`. Cleared on
  /// [clearAccessToken] / logout.
  String? _accessToken;

  /// When [_accessToken] becomes invalid. Used to refresh
  /// opportunistically before sending requests that would otherwise
  /// land a 401.
  DateTime? _accessExpiresAt;

  /// Single in-flight refresh. Concurrent 401s share the same Future so
  /// we only mint one new token pair per cluster of expired requests.
  /// Critical: parallel refresh calls would each consume the
  /// (single-use) refresh token, and the second call would force the
  /// server to revoke the entire refresh-token family for the worker.
  Future<void>? _pendingRefresh;

  // ---- access-token plumbing ----------------------------------------

  /// Stores tokens received from `/auth/otp/verify` or
  /// `/auth/profile-setup`. The refresh half goes to secure storage
  /// (long-lived); the access half stays in memory only (short-lived).
  Future<void> cacheTokens({
    required String accessToken,
    required String refreshToken,
    required DateTime accessExpiresAt,
    required DateTime refreshExpiresAt,
  }) async {
    _accessToken = accessToken;
    _accessExpiresAt = accessExpiresAt.toUtc();
    await _storage.writeRefreshToken(
      refreshToken: refreshToken,
      refreshExpiresAt: refreshExpiresAt,
    );
  }

  /// Drop the in-memory access token. Used on logout / hard reset.
  void clearAccessToken() {
    _accessToken = null;
    _accessExpiresAt = null;
  }

  // ---- public surface ------------------------------------------------

  Future<Map<String, dynamic>> get(
    String path, {
    bool authenticated = false,
    Map<String, String>? query,
  }) =>
      _send('GET', path,
          authenticated: authenticated, query: query);

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool authenticated = false,
    bool idempotent = false,
    String? idempotencyAction,
  }) =>
      _send('POST', path,
          body: body,
          authenticated: authenticated,
          idempotent: idempotent,
          idempotencyAction: idempotencyAction);

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    bool authenticated = true,
  }) =>
      _send('PATCH', path, body: body, authenticated: authenticated);

  Future<Map<String, dynamic>> delete(
    String path, {
    Object? body,
    bool authenticated = true,
  }) =>
      _send('DELETE', path, body: body, authenticated: authenticated);

  /// Multipart upload — used by `POST /uploads`. The response body
  /// is parsed and returned in the same shape as JSON endpoints.
  Future<Map<String, dynamic>> upload(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    Map<String, String> fields = const <String, String>{},
    bool authenticated = true,
  }) async {
    if (!ApiConfig.isConfigured) {
      throw const ApiException(
        statusCode: 0,
        code: 'NOT_CONFIGURED',
        message:
            'Backend URL is not set. Update ApiConfig.baseUrl in '
            'lib/core/api/api_config.dart.',
      );
    }
    if (authenticated) await _ensureFreshAccessToken();

    final uri = _buildUri(path, null);
    final mime = contentType.split('/');
    final media = mime.length == 2
        ? MediaType(mime[0], mime[1])
        : MediaType('application', 'octet-stream');

    // Guard against the most common silent-fail: the file bytes are
    // empty (image_picker's cache dir was cleaned, or the path is
    // wrong). The server would receive a multipart with a zero-byte
    // `file` part and respond with a "missing image" / 400 — looking
    // like a wire-format bug when it's actually a vanished file.
    if (bytes.isEmpty) {
      throw const ApiException(
        statusCode: 0,
        code: 'EMPTY_FILE',
        message: "The photo file is empty or unreadable. Retake.",
      );
    }

    final request = http.MultipartRequest('POST', uri)
      ..fields.addAll(fields)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: media,
      ));

    if (kDebugMode) {
      debugPrint(
        '[api:upload] POST $uri\n'
        '  field "purpose" = ${fields['purpose']}\n'
        '  field "file"    filename=$filename  size=${bytes.length}B  '
        'mime=${media.mimeType}\n'
        '  user headers = ${{
          'Accept': 'application/json',
          'Accept-Language': ApiConfig.acceptLanguage,
          'Authorization': _accessToken != null ? 'Bearer <set>' : '<none>',
        }}',
      );
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': ApiConfig.acceptLanguage,
      'X-App-Version': ApiConfig.appVersion,
      'X-Device-Platform': _platform,
    };
    if (authenticated && _accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    request.headers.addAll(headers);

    http.StreamedResponse streamed;
    try {
      streamed = await _client
          .send(request)
          .timeout(ApiConfig.receiveTimeout);
    } on SocketException catch (e) {
      throw ApiException.fromSocket(e);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        code: 'TIMEOUT',
        message: 'The upload took too long. Try again.',
      );
    }
    final response = await http.Response.fromStream(streamed);
    if (kDebugMode) {
      final preview = response.body.length > 600
          ? '${response.body.substring(0, 600)}…(${response.body.length}B total)'
          : response.body;
      debugPrint(
        '[api:upload] ← ${response.statusCode}\n'
        '  body: $preview',
      );
    }
    return _parse(response);
  }

  void close() => _client.close();

  // ---- core ----------------------------------------------------------

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool authenticated = false,
    bool idempotent = false,
    String? idempotencyAction,
    bool isRetry = false,
  }) async {
    if (!ApiConfig.isConfigured) {
      throw const ApiException(
        statusCode: 0,
        code: 'NOT_CONFIGURED',
        message:
            'Backend URL is not set. Update ApiConfig.baseUrl in '
            'lib/core/api/api_config.dart.',
      );
    }

    if (idempotent && idempotencyAction == null) {
      // Without an action key we can't reuse the same UUID across
      // retries — that would defeat the entire point of the header.
      // Repos must pass `idempotencyAction: '<verb>:<resource-id>'`.
      throw ArgumentError(
        'idempotent=true requires idempotencyAction (e.g. "apply:job_123"). '
        'See lib/core/api/idempotency_store.dart.',
      );
    }

    if (authenticated) {
      await _ensureFreshAccessToken();
    }

    final uri = _buildUri(path, query);
    final headers = await _buildHeaders(
      authenticated: authenticated,
      hasBody: body != null,
      idempotencyAction: idempotent ? idempotencyAction : null,
    );

    http.Response response;
    try {
      response = await _dispatch(method, uri, headers, body)
          .timeout(ApiConfig.receiveTimeout);
    } on SocketException catch (e) {
      // Network error — keep the idempotency key alive for the retry.
      throw ApiException.fromSocket(e);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        code: 'TIMEOUT',
        message: 'The request took too long. Try again.',
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK',
        message: e.message,
      );
    }

    if (response.statusCode == 401 && authenticated && !isRetry) {
      // Try refresh once. If it succeeds, re-issue the original call.
      // If it fails, the refresh path itself throws and we surface the
      // auth-required state to the caller (auth state machine clears
      // tokens and routes to login).
      final refreshed = await _tryRefresh();
      if (refreshed) {
        return _send(method, path,
            body: body,
            query: query,
            authenticated: authenticated,
            idempotent: idempotent,
            idempotencyAction: idempotencyAction,
            isRetry: true);
      }
    }

    // Non-5xx → terminal. Drop the idempotency key so the next call
    // against the same logical action mints a fresh UUID. 5xx and the
    // network errors above keep the key (we already returned early
    // for those).
    final isTerminal = response.statusCode < 500;
    if (idempotent && isTerminal && idempotencyAction != null) {
      await _idempotency.clear(idempotencyAction);
    }

    return _parse(response);
  }

  Future<http.Response> _dispatch(
    String method,
    Uri uri,
    Map<String, String> headers,
    Object? body,
  ) {
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        return _client.get(uri, headers: headers);
      case 'POST':
        return _client.post(uri, headers: headers, body: encoded);
      case 'PATCH':
        return _client.patch(uri, headers: headers, body: encoded);
      case 'DELETE':
        return _client.delete(uri, headers: headers, body: encoded);
    }
    throw ArgumentError.value(method, 'method', 'Unsupported HTTP verb');
  }

  Uri _buildUri(String path, Map<String, String>? query) {
    final normalizedBase = ApiConfig.baseUrl.endsWith('/')
        ? ApiConfig.baseUrl.substring(0, ApiConfig.baseUrl.length - 1)
        : ApiConfig.baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final raw = '$normalizedBase$normalizedPath';
    final base = Uri.parse(raw);
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      ...query,
    });
  }

  Future<Map<String, String>> _buildHeaders({
    required bool authenticated,
    required bool hasBody,
    required String? idempotencyAction,
  }) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Accept-Language': ApiConfig.acceptLanguage,
      'X-App-Version': ApiConfig.appVersion,
      'X-Device-Platform': _platform,
    };
    if (hasBody) {
      headers['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (idempotencyAction != null) {
      headers['Idempotency-Key'] =
          await _idempotency.obtain(idempotencyAction);
    }
    if (authenticated && _accessToken != null && _accessToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  Map<String, dynamic> _parse(http.Response response) {
    final body = response.body;
    final decoded = body.isEmpty ? const <String, dynamic>{} : _decode(body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final envelope = decoded['error'];
    if (envelope is Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        code: envelope['code'] as String? ?? 'UNKNOWN',
        message: envelope['message'] as String? ?? 'Something went wrong.',
        details: envelope['details'] is Map<String, dynamic>
            ? envelope['details'] as Map<String, dynamic>
            : null,
      );
    }

    throw ApiException(
      statusCode: response.statusCode,
      code: 'UNKNOWN',
      message: 'Unexpected server response (${response.statusCode}).',
    );
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final parsed = jsonDecode(body);
      return parsed is Map<String, dynamic>
          ? parsed
          : <String, dynamic>{'data': parsed};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  // ---- token refresh ------------------------------------------------

  /// Refreshes the access token if it's missing or has fewer than
  /// [ApiConfig.refreshLeeway] seconds of life left.
  ///
  /// Cold-start path: `_accessToken` starts null, so the first
  /// protected call lands here, hits `/auth/refresh` with the
  /// persisted refresh token, and continues with the fresh pair.
  Future<void> _ensureFreshAccessToken() async {
    if (_accessToken == null || _accessToken!.isEmpty) {
      await _tryRefresh();
      return;
    }
    final expiresAt = _accessExpiresAt;
    if (expiresAt == null) return;
    final timeLeft = expiresAt.difference(DateTime.now().toUtc());
    if (timeLeft > ApiConfig.refreshLeeway) return;
    await _tryRefresh();
  }

  Future<bool> _tryRefresh() {
    final pending = _pendingRefresh;
    if (pending != null) {
      return pending.then((_) => true).catchError((_) => false);
    }
    final fresh = _runRefresh();
    _pendingRefresh = fresh;
    return fresh.then<bool>((_) => true).catchError((_) {
      return false;
    }).whenComplete(() => _pendingRefresh = null);
  }

  Future<void> _runRefresh() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const ApiException(
        statusCode: 401,
        code: 'TOKEN_INVALID',
        message: 'Session expired. Please log in again.',
      );
    }

    final uri = _buildUri('/auth/refresh', null);
    final response = await _client
        .post(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json; charset=utf-8',
            'Accept-Language': ApiConfig.acceptLanguage,
            'X-App-Version': ApiConfig.appVersion,
            'X-Device-Platform': _platform,
          },
          body: jsonEncode(<String, String>{'refresh_token': refreshToken}),
        )
        .timeout(ApiConfig.receiveTimeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Treat any non-2xx on refresh as a hard failure — clear local
      // state so the splash gate re-resolves to unauthenticated on
      // next read.
      clearAccessToken();
      await _storage.clearSession();
      throw const ApiException(
        statusCode: 401,
        code: 'TOKEN_INVALID',
        message: 'Session expired. Please log in again.',
      );
    }

    // Single-use rotation: persist the new pair before any other
    // protected call can reuse the (now-invalidated) old refresh
    // token.
    final json = _decode(response.body);
    _accessToken = json['access_token'] as String;
    _accessExpiresAt =
        DateTime.parse(json['access_expires_at'] as String).toUtc();
    await _storage.writeRefreshToken(
      refreshToken: json['refresh_token'] as String,
      refreshExpiresAt:
          DateTime.parse(json['refresh_expires_at'] as String).toUtc(),
    );
  }
}

String get _platform {
  if (kIsWeb) return 'web';
  if (Platform.isIOS) return 'ios';
  if (Platform.isAndroid) return 'android';
  return 'other';
}
