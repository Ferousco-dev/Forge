import 'dart:io';

/// Error envelope from the backend, matching `00_README.md`:
///
/// ```json
/// { "error": { "code": "VALIDATION_FAILED", "message": "...", "details": {} } }
/// ```
///
/// HTTP status carries the category; `code` carries the specifics.
/// The mobile UI surfaces [message] directly to the user when it's
/// human-friendly; [code] drives programmatic branching (token refresh,
/// step navigation, retry policy).
class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.details,
  });

  /// HTTP status. 0 means the request never reached the server (timeout,
  /// DNS failure, no connectivity).
  final int statusCode;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  /// True when no HTTP response was received. Drives the offline banner.
  bool get isNetwork => statusCode == 0;

  /// True when the access token expired or was malformed. The API client
  /// uses this to trigger a refresh + retry; if the refresh itself fails
  /// the auth state machine clears local tokens and routes to login.
  bool get isUnauthorized => statusCode == 401;

  /// Generic offline-style fallback when no envelope was parseable.
  factory ApiException.offline() => const ApiException(
        statusCode: 0,
        code: 'OFFLINE',
        message: "You're offline. Check your connection and try again.",
      );

  /// Wraps a low-level socket failure with a friendly message.
  factory ApiException.fromSocket(SocketException e) => ApiException(
        statusCode: 0,
        code: 'NETWORK',
        message: e.message.isEmpty
            ? "We couldn't reach the server. Try again."
            : e.message,
      );

  @override
  String toString() => 'ApiException($statusCode $code: $message)';
}
