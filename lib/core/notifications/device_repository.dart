import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../storage/session_storage.dart';

/// Backend-facing surface for device + push-token registration.
///
/// Backs `POST /me/devices` and `DELETE /me/devices/:device_id` from
/// `endpoint_resources/24_push_notifications.md` (and `18_settings.md`
/// for the upstream endpoint). The mobile calls into this from:
///
/// - The notification permission screen, right after the OS-level
///   grant — gets the FCM token + posts the row.
/// - The push service, on `onTokenRefresh` — re-registers the same
///   `device_id` with the new token (server UPSERTs).
/// - The auth/logout flow, before clearing tokens — best-effort
///   `DELETE` so the row goes away cleanly.
class DeviceRepository {
  DeviceRepository({
    required ApiClient client,
    required SessionStorage storage,
  })  : _client = client,
        _storage = storage;

  final ApiClient _client;
  final SessionStorage _storage;

  /// `POST /me/devices`. UPSERT semantics on the server — calling with
  /// the same `device_id` twice updates the token + `app_version`,
  /// never duplicates.
  Future<void> registerDevice({
    required String pushToken,
  }) async {
    final deviceId = await _storage.readOrCreateDeviceId();
    final appVersion = await _readAppVersion();

    await _client.post(
      '/me/devices',
      authenticated: true,
      body: <String, dynamic>{
        'platform': Platform.isIOS ? 'ios' : 'android',
        'push_token': pushToken,
        'device_id': deviceId,
        'app_version': appVersion,
      },
    );

    await _storage.writeLastRegisteredPushToken(pushToken);
  }

  /// Local-only logout cleanup for the push subsystem.
  ///
  /// The backend (verified against the live OpenAPI spec on
  /// 2026-05-10) does **not** implement `DELETE /me/devices/:device_id`
  /// — the canonical cleanup path is the send job's `NotRegistered`
  /// pruning, which deletes rows when a stale token returns an error
  /// from FCM. So we just clear the local cached token; the server-
  /// side row will be garbage-collected the next time someone tries
  /// to push to it.
  ///
  /// Kept as a method (not inlined) so the logout flow has a single
  /// hook to call — and so re-introducing the network call is one
  /// edit if the backend ever adds the endpoint.
  Future<void> unregisterDevice() async {
    await _storage.clearLastRegisteredPushToken();
  }

  /// True when the device's current FCM token matches the one we
  /// last successfully POSTed. Used by the push service to skip
  /// redundant registration calls on warm starts.
  Future<bool> isAlreadyRegistered(String currentToken) async {
    final cached = await _storage.readLastRegisteredPushToken();
    return cached == currentToken;
  }

  /// Read `pubspec.yaml` version + build. Falls back to a static
  /// string if the platform channel that powers `PackageInfo` isn't
  /// available (test harness).
  Future<String> _readAppVersion() async {
    try {
      const channel = MethodChannel('plugins.flutter.io/package_info');
      final info = await channel.invokeMapMethod<String, dynamic>('getAll');
      final v = info?['version'];
      final b = info?['buildNumber'];
      if (v is String && b is String) return '$v+$b';
    } catch (_) {
      // Fall through.
    }
    return '1.0.0+1';
  }
}
