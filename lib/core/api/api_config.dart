/// Single source of truth for the backend base URL and global request
/// headers. Drop the production URL into [baseUrl] — every API call
/// in the app reads from here.
///
/// Conventions match `endpoint_resources/00_README.md`:
/// - Versioned prefix lives in the URL itself (`/v1`).
/// - JSON in / JSON out (uploads use multipart — see 22_uploads.md).
/// - All timestamps ISO 8601 UTC; mobile converts at the display layer.
class ApiConfig {
  const ApiConfig._();

  /// Backend base URL — production deployment on Railway.
  ///
  /// Swagger UI:   https://forgebe-production.up.railway.app/docs
  /// OpenAPI JSON: https://forgebe-production.up.railway.app/v1/openapi.json
  ///
  /// Backend route shape: `/v1/<resource>` (single prefix, confirmed
  /// against the live OpenAPI spec on 2026-05-10 — e.g.
  /// `POST /v1/auth/otp/request`, `POST /v1/me/devices`). Request
  /// paths in this codebase start with a leading `/` and do **not**
  /// include `v1` themselves; this base URL absorbs the prefix.
  static const String baseUrl =
      'https://forgebe-production.up.railway.app/v1';

  /// Sent on every request. Matches `00_README.md` "Common headers".
  static const String acceptLanguage = 'en-NG';

  /// Bumped on every release. Backend can warn on deprecated builds.
  static const String appVersion = '1.0.0+1';

  /// Networking timeouts. Tight enough to surface a real failure quickly
  /// on flaky networks, generous enough to ride out a 4G handoff.
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Refresh the access token when it has fewer than this many seconds
  /// left. Per `01_auth.md` notes for backend.
  static const Duration refreshLeeway = Duration(seconds: 60);

  /// Returns true while the placeholder is still in place. Used by the
  /// splash gate to short-circuit network calls in the demo build.
  static bool get isConfigured =>
      baseUrl.isNotEmpty && !baseUrl.startsWith('REPLACE_ME');
}
