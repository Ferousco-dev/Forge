import 'package:flutter/foundation.dart';

import '../../../core/mock/models.dart';

/// Local mirror of the OTP flow discriminator sent to
/// `POST /auth/otp/request`. The mobile uses [OtpFlow] to pick copy and
/// post-verify routing; the server uses it to decide whether the phone
/// must already exist (login) or must not (signup).
enum OtpFlow {
  login,
  signup;

  String get wire => name; // serializes to "login" / "signup"
}

/// Channel the server used (or that the caller is requesting) to deliver
/// the OTP. `auto` is request-only — the server decides and echoes back
/// one of the concrete values (`whatsapp` / `sms` / `push`).
///
/// See `endpoint_resources/24b_fcm_and_otp_channels.md` for the rule the
/// server uses to pick.
enum OtpChannel {
  auto,
  whatsapp,
  sms,
  push;

  String get wire => name;

  static OtpChannel fromWire(String? raw) {
    switch (raw) {
      case 'whatsapp':
        return OtpChannel.whatsapp;
      case 'sms':
        return OtpChannel.sms;
      case 'push':
        return OtpChannel.push;
      case 'auto':
        return OtpChannel.auto;
      default:
        // Older servers don't return `channel` at all — assume SMS so
        // the UI copy ("Check your messages") still matches what the
        // user actually got.
        return OtpChannel.sms;
    }
  }
}

/// Result of `POST /auth/otp/request`.
@immutable
class OtpChallenge {
  const OtpChallenge({
    required this.challengeId,
    required this.expiresAt,
    required this.resendAfterSeconds,
    this.channel = OtpChannel.sms,
    this.channelHint,
  });

  final String challengeId;
  final DateTime expiresAt;
  final int resendAfterSeconds;

  /// Channel the server actually delivered through. Never `auto` —
  /// the server resolves `auto` to one of the concrete channels before
  /// responding.
  final OtpChannel channel;

  /// Pre-localised hint string the server sends so the OTP screen can
  /// say "Code sent to your WhatsApp" without hardcoding the channel
  /// label. Null when the server didn't include it — the screen falls
  /// back to a channel-derived default.
  final String? channelHint;

  factory OtpChallenge.fromJson(Map<String, dynamic> json) {
    return OtpChallenge(
      challengeId: json['challenge_id'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toUtc(),
      resendAfterSeconds:
          (json['resend_after_seconds'] as num?)?.toInt() ?? 30,
      channel: OtpChannel.fromWire(json['channel'] as String?),
      channelHint: json['channel_hint'] as String?,
    );
  }
}

/// Result of `POST /auth/otp/verify`. Login returns a populated worker;
/// signup returns `worker = null` and `needsProfileSetup = true`.
@immutable
class OtpVerification {
  const OtpVerification({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.needsProfileSetup,
    this.worker,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final Worker? worker;
  final bool needsProfileSetup;

  factory OtpVerification.fromJson(Map<String, dynamic> json) {
    final workerJson = json['worker'];
    return OtpVerification(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      accessExpiresAt:
          DateTime.parse(json['access_expires_at'] as String).toUtc(),
      refreshExpiresAt:
          DateTime.parse(json['refresh_expires_at'] as String).toUtc(),
      worker: workerJson is Map<String, dynamic>
          ? Worker.fromJson(workerJson)
          : null,
      needsProfileSetup: json['needs_profile_setup'] as bool? ?? false,
    );
  }
}
