import '../../../core/api/api_client.dart';
import '../../../core/api/api_exception.dart';
import '../../../core/mock/models.dart';
import '../../../core/storage/session_storage.dart';
import 'auth_models.dart';

/// Backend-facing surface for the auth feature.
///
/// Responsible for:
/// - calling the five endpoints in `endpoint_resources/01_auth.md`,
/// - persisting tokens + the cached worker into [SessionStorage],
/// - normalising the local 10-digit phone into E.164 (`+234XXXXXXXXXX`).
///
/// Returns plain DTOs; UI maps them onto navigation. Errors bubble up
/// as [ApiException] — screens catch and inline the message.
class AuthRepository {
  AuthRepository({
    required ApiClient client,
    required SessionStorage storage,
  })  : _client = client,
        _storage = storage;

  final ApiClient _client;
  final SessionStorage _storage;

  // ---- helpers -------------------------------------------------------

  /// Local 10-digit phone → E.164 (`+234XXXXXXXXXX`). The phone-entry
  /// scaffold guarantees 10 digits before this call.
  static String toE164(String localTenDigit) {
    final digits = localTenDigit.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '+234$digits';
    if (digits.length == 11 && digits.startsWith('0')) {
      return '+234${digits.substring(1)}';
    }
    if (digits.startsWith('234')) return '+$digits';
    return localTenDigit;
  }

  // ---- endpoints -----------------------------------------------------

  /// `POST /auth/otp/request` — sends an OTP to [localPhone] for the
  /// chosen [flow]. The server picks the channel via the rule in
  /// `endpoint_resources/24b_fcm_and_otp_channels.md`:
  ///
  /// - returning user with an active FCM device → push
  /// - else → WhatsApp (primary)
  /// - WhatsApp send failed → SMS fallback
  ///
  /// Mobile always sends [preferredChannel] = `OtpChannel.auto` from
  /// production. The override exists for the "Try a different channel"
  /// sheet (Phase 3) and for support tooling.
  Future<OtpChallenge> requestOtp({
    required String localPhone,
    required OtpFlow flow,
    OtpChannel preferredChannel = OtpChannel.auto,
  }) async {
    final json = await _client.post(
      '/auth/otp/request',
      authenticated: false,
      body: <String, String>{
        'phone': toE164(localPhone),
        'flow': flow.wire,
        'preferred_channel': preferredChannel.wire,
      },
    );
    return OtpChallenge.fromJson(json);
  }

  /// `POST /auth/otp/verify` — exchanges the SMS code for a token pair.
  /// On success persists tokens (and the worker, when login). For
  /// signup, also flags the session as `needs_profile_setup` so a
  /// subsequent cold start routes back to profile-setup.
  Future<OtpVerification> verifyOtp({
    required String challengeId,
    required String code,
  }) async {
    final json = await _client.post(
      '/auth/otp/verify',
      authenticated: false,
      body: <String, String>{
        'challenge_id': challengeId,
        'code': code,
      },
    );
    final verification = OtpVerification.fromJson(json);

    // Hand the freshly-issued tokens to the API client. The refresh
    // half is persisted (long-lived); the access half lives in
    // memory only — see `ApiClient.cacheTokens`.
    await _client.cacheTokens(
      accessToken: verification.accessToken,
      refreshToken: verification.refreshToken,
      accessExpiresAt: verification.accessExpiresAt,
      refreshExpiresAt: verification.refreshExpiresAt,
    );
    await _storage.writeNeedsProfileSetup(verification.needsProfileSetup);
    await _storage.writeWorker(verification.worker?.toJson());

    return verification;
  }

  /// `POST /auth/profile-setup` — completes signup. ⚡ Idempotent —
  /// the same UUID is reused across retries until a terminal response
  /// (only one profile-setup ever runs per worker, so the action key
  /// is constant).
  Future<Worker> completeProfileSetup({
    required String name,
    required String primarySkill,
    required double preferredRadiusKm,
    String? photoUploadId,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'primary_skill': primarySkill,
      'preferred_radius_km': preferredRadiusKm,
      if (photoUploadId != null && photoUploadId.isNotEmpty)
        'photo_upload_id': photoUploadId,
    };

    final json = await _client.post(
      '/auth/profile-setup',
      authenticated: true,
      idempotent: true,
      idempotencyAction: 'profile-setup',
      body: body,
    );

    final workerJson = json['worker'] as Map<String, dynamic>;
    final worker = Worker.fromJson(workerJson);

    await _storage.writeWorker(workerJson);
    await _storage.writeNeedsProfileSetup(false);
    return worker;
  }

  /// `POST /auth/logout` — best-effort. Per the spec we always clear
  /// local state even if the server call fails.
  Future<void> logout() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken != null && refreshToken.isNotEmpty) {
      try {
        await _client.post(
          '/auth/logout',
          authenticated: true,
          body: <String, String>{'refresh_token': refreshToken},
        );
      } on ApiException {
        // Logout is best-effort. Swallow — local state is the source
        // of truth for the next launch.
      }
    }
    _client.clearAccessToken();
    await _storage.clearSession();
  }

  // ---- session bootstrap -------------------------------------------

  /// Resolves the on-disk session state at app cold-start. Read once
  /// from the splash gate.
  ///
  /// We only persist the refresh token now — the access token lives
  /// in memory and is minted on the first protected call. So
  /// "authenticated" means "we have a refresh token whose expiry
  /// hasn't passed". The first protected call from the next screen
  /// will exchange it for a fresh access token.
  Future<SessionSnapshot> resolveSession() async {
    final refreshToken = await _storage.readRefreshToken();
    final refreshExpiresAt = await _storage.readRefreshExpiresAt();
    final cachedWorker = await _storage.readWorker();
    final needsProfileSetup = await _storage.readNeedsProfileSetup();

    final hasRefresh = refreshToken != null && refreshToken.isNotEmpty;
    final refreshAlive = refreshExpiresAt != null &&
        refreshExpiresAt.isAfter(DateTime.now().toUtc());

    if (!hasRefresh || !refreshAlive) {
      // Either no session at all or the long-lived refresh token has
      // expired — both states force a fresh login.
      if (hasRefresh && !refreshAlive) {
        await _storage.clearSession();
      }
      return const Unauthenticated();
    }

    if (needsProfileSetup) {
      return const PendingProfileSetup();
    }

    return Authenticated(
      worker: cachedWorker == null ? null : Worker.fromJson(cachedWorker),
    );
  }
}

/// Discriminated session shape consumed by the splash gate. Use
/// pattern-matching (`switch (snapshot) { case Authenticated() ... }`)
/// at the call site — Dart's exhaustiveness check guarantees every
/// branch is handled.
sealed class SessionSnapshot {
  const SessionSnapshot();
}

class Unauthenticated extends SessionSnapshot {
  const Unauthenticated();
}

class PendingProfileSetup extends SessionSnapshot {
  const PendingProfileSetup();
}

class Authenticated extends SessionSnapshot {
  const Authenticated({this.worker});
  final Worker? worker;
}
