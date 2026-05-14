import '../../../core/api/api_client.dart';
import '../../../core/mock/models.dart';

/// `18_settings.md` — preferences + account + phone change + devices.
class PreferencesRepository {
  PreferencesRepository({required ApiClient client}) : _client = client;
  final ApiClient _client;

  Future<RemotePreferences> fetch() async {
    final json = await _client.get(
      '/me/preferences',
      authenticated: true,
    );
    return RemotePreferences.fromJson(json);
  }

  /// PATCH semantics — only present fields update. Pass `null` to skip
  /// a group; pass a fresh value to overwrite that group's flags.
  Future<RemotePreferences> patch({
    NotificationToggles? notifications,
    PrivacyToggles? privacy,
  }) async {
    final body = <String, dynamic>{
      if (notifications != null) 'notifications': notifications.toJson(),
      if (privacy != null) 'privacy': privacy.toJson(),
    };
    final json = await _client.patch(
      '/me/preferences',
      authenticated: true,
      body: body,
    );
    return RemotePreferences.fromJson(json);
  }

  Future<DeleteAccountResult> deleteAccount() async {
    final json = await _client.post(
      '/me/account/delete',
      authenticated: true,
    );
    return DeleteAccountResult(
      requestId: json['deletion_request_id'] as String,
      scheduledAt:
          DateTime.parse(json['scheduled_at'] as String).toUtc(),
      completesAt:
          DateTime.parse(json['completes_at'] as String).toUtc(),
    );
  }

  /// Phone-change step 1. Same response shape as the OTP request.
  Future<Map<String, dynamic>> requestPhoneChange(String newPhone) async {
    return _client.post(
      '/me/phone/change/request',
      authenticated: true,
      body: <String, String>{'new_phone': newPhone},
    );
  }

  Future<Map<String, dynamic>> confirmPhoneChange({
    required String challengeId,
    required String code,
  }) async {
    return _client.post(
      '/me/phone/change/confirm',
      authenticated: true,
      body: <String, String>{
        'challenge_id': challengeId,
        'code': code,
      },
    );
  }

  Future<void> registerDevice({
    required String platform,
    required String pushToken,
    required String deviceId,
    required String appVersion,
  }) async {
    await _client.post(
      '/me/devices',
      authenticated: true,
      body: <String, String>{
        'platform': platform,
        'push_token': pushToken,
        'device_id': deviceId,
        'app_version': appVersion,
      },
    );
  }
}

class DeleteAccountResult {
  const DeleteAccountResult({
    required this.requestId,
    required this.scheduledAt,
    required this.completesAt,
  });
  final String requestId;
  final DateTime scheduledAt;
  final DateTime completesAt;
}
