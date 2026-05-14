import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
// ignore: unnecessary_import — analyser thinks material re-exports
// Clipboard; on this Flutter version the class is only visible via
// the services import.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/otp_input.dart';
import '../../../shared/widgets/primary_button.dart';
import '../data/auth_models.dart';
import '../state/auth_state.dart';

/// Payload passed into `/auth/otp` via go_router's `extra`. Carries
/// everything the OTP screen needs to verify without touching the
/// repository again until the user submits a code.
class OtpFlowExtra {
  const OtpFlowExtra({
    required this.phone,
    required this.flow,
    required this.challengeId,
    required this.expiresAt,
    required this.resendAfterSeconds,
    this.channel = OtpChannel.sms,
    this.channelHint,
  });

  /// 10-digit local number (no country code) — display only.
  final String phone;

  final OtpFlow flow;

  /// Opaque server-side handle returned by `/auth/otp/request`.
  final String challengeId;

  /// When the OTP becomes invalid (UI hides the input + dims the CTA).
  final DateTime expiresAt;

  /// Cooldown before the user can ask the server for a new code.
  final int resendAfterSeconds;

  /// Channel the server delivered through. Drives the subtitle copy on
  /// the OTP screen ("Check your WhatsApp" vs "Check your messages").
  final OtpChannel channel;

  /// Optional server-provided label for the destination (e.g.
  /// "your WhatsApp"). When null the screen derives a default from
  /// [channel].
  final String? channelHint;
}

/// 6-digit OTP verification.
///
/// Behavior per the brief:
/// - Auto-advance and paste-friendly via [OtpInput].
/// - "Resend code in 0:30" countdown becomes a tappable "Resend code"
///   link after it elapses.
/// - "Verify" CTA is disabled until all 6 digits are entered.
/// - Wrong-code path renders inline error styling on the boxes.
///
/// Calls `POST /auth/otp/verify`. On success, the auth repository
/// stores tokens (and the worker, for login). Routing splits on
/// `needs_profile_setup` from the response — the same OTP endpoint
/// serves both flows.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key, required this.extra});

  final OtpFlowExtra extra;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  String _value = '';
  String? _errorText;
  bool _submitting = false;
  bool _resending = false;

  /// Resend cooldown — sourced from the original challenge so the UI
  /// matches the server's rate limit. Refreshed on every successful
  /// resend.
  late Duration _resendCountdown;
  late Duration _remaining;
  Timer? _ticker;

  /// Most recent challenge id. Updated when the user resends — the
  /// new code is bound to a new challenge, so verify must use the
  /// fresh handle.
  late String _challengeId;

  /// Channel the latest challenge was delivered through. Starts from
  /// the route-extra, refreshed on every resend so the subtitle and
  /// the "Open WhatsApp" affordance always reflect where the most
  /// recent code actually went.
  late OtpChannel _channel;

  /// Server-provided destination label (e.g. "your WhatsApp"). Null
  /// after a resend where the server didn't echo it; the UI then falls
  /// back to a channel-derived default.
  String? _channelHint;

  /// Drives the OTP input from outside — used by the "Paste OTP"
  /// button and the auto-paste-on-mount fast path.
  final OtpInputController _otpController = OtpInputController();

  @override
  void initState() {
    super.initState();
    _challengeId = widget.extra.challengeId;
    _channel = widget.extra.channel;
    _channelHint = widget.extra.channelHint;
    _resendCountdown = Duration(seconds: widget.extra.resendAfterSeconds);
    _startCountdown();
    // Auto-paste from clipboard once the first frame is up. If the
    // worker just copied a 6-digit code from the Railway log they get
    // an instant prefill — no Paste button tap needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryPasteFromClipboard(silent: true);
    });
  }

  /// Read the OS clipboard, extract 6 digits, and pump them into the
  /// OTP boxes. When [silent] is true, no snackbar fires when nothing
  /// usable is found — used by the on-mount auto-paste path so the
  /// screen doesn't shout at users who just opened it fresh.
  Future<void> _tryPasteFromClipboard({bool silent = false}) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text ?? '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 6) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(AppSpacing.base),
            content: Text(
              'No 6-digit code on the clipboard — copy it first.',
            ),
          ));
      }
      return;
    }
    _otpController.fill(digits.substring(0, 6));
  }

  void _startCountdown() {
    _remaining = _resendCountdown;
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      setState(() {
        if (_remaining.inSeconds <= 1) {
          _remaining = Duration.zero;
          t.cancel();
        } else {
          _remaining -= const Duration(seconds: 1);
        }
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  /// True when we should send a returning user through the
  /// notification permission screen after login. We only ever ask
  /// when the OS state is "not determined" — granted or previously
  /// denied users go straight to home, since re-prompting them is
  /// pointless (denied is sticky until the user changes it in system
  /// Settings; granted means we're already wired up).
  ///
  /// `getNotificationSettings()` is a pure status read — it doesn't
  /// trigger the OS prompt. The actual prompt fires from inside
  /// `NotificationPermissionScreen.onPrimary`.
  Future<bool> _shouldAskNotificationPermission() async {
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      return settings.authorizationStatus ==
          AuthorizationStatus.notDetermined;
    } catch (_) {
      // FCM not configured (e.g. local dev without GoogleService-Info)
      // — don't block the worker on the gate.
      return false;
    }
  }

  Future<void> _verify() async {
    if (_value.length != 6 || _submitting) return;
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      final result = await ref.read(authRepositoryProvider).verifyOtp(
            challengeId: _challengeId,
            code: _value,
          );

      // Force the splash gate / any auth-aware listeners to re-resolve
      // session state from secure storage on the next read.
      ref.invalidate(authSessionProvider);

      // Re-bind this device's FCM token to the freshly-authenticated
      // worker on the server. Without this, a user who logs out and
      // signs back in (or signs in as a different worker) would keep
      // the previous worker_id on the `/me/devices` row until the
      // next cold start — meaning pushes meant for them would either
      // miss or hit the wrong account.
      //
      // Fire-and-forget: the verify CTA shouldn't block on a side
      // call. `registerIfPermitted` is internally debounced (no-op
      // when the token already matches the cached one) and silently
      // returns for users who haven't granted permission yet.
      unawaited(
        ref
            .read(notificationsServiceProvider)
            .registerIfPermitted()
            .catchError((_) {}),
      );

      if (!mounted) return;
      if (result.needsProfileSetup) {
        // Signup branch routes through the AI-verified selfie step
        // before profile setup — see endpoint_resources/23_liveness.md.
        // Login branch never lands here (the server returns
        // needs_profile_setup=false for an already-set-up worker).
        context.go(RoutePaths.livenessCapture);
      } else {
        // Login on a fresh install: the signup permission gates never
        // ran on this device, so the OS prompt for POST_NOTIFICATIONS
        // (Android 13+) / UNUserNotificationCenter (iOS) has never
        // been shown. Without it, FCM can't deliver job alerts,
        // payment confirms, or — most importantly for the worker —
        // OTP-via-push on the NEXT login (the server only picks the
        // push channel when this device is registered against the
        // account). Detect the "never asked" state and route through
        // the existing notification permission screen, which fires
        // the prompt and then forwards to home. Users who've already
        // decided (granted or denied) bypass and go straight in.
        final shouldAskNotif = await _shouldAskNotificationPermission();
        if (!mounted) return;
        if (shouldAskNotif) {
          context.go(RoutePaths.permissionsNotifications);
        } else {
          context.go(RoutePaths.jobs);
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = e.message;
      });
    }
  }

  Future<void> _resend() async {
    if (_remaining > Duration.zero || _resending) return;
    setState(() {
      _resending = true;
      _errorText = null;
    });
    try {
      final challenge = await ref.read(authRepositoryProvider).requestOtp(
            localPhone: widget.extra.phone,
            flow: widget.extra.flow,
          );
      if (!mounted) return;
      setState(() {
        _challengeId = challenge.challengeId;
        _channel = challenge.channel;
        _channelHint = challenge.channelHint;
        _resendCountdown = Duration(seconds: challenge.resendAfterSeconds);
        _resending = false;
      });
      _startCountdown();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(AppSpacing.base),
            content: Text('A new code is on its way via ${_channelLabel()}.'),
          ),
        );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _resending = false;
        _errorText = e.message;
      });
    }
  }

  String _formattedPhone() {
    final p = widget.extra.phone;
    if (p.length != 10) return '+234 $p';
    return '+234 ${p.substring(0, 3)} ${p.substring(3, 6)} ${p.substring(6)}';
  }

  /// Short channel name used in the resend snackbar ("...on its way
  /// via WhatsApp"). Falls back to "SMS" so older servers that don't
  /// echo a channel still get a sensible string.
  String _channelLabel() {
    switch (_channel) {
      case OtpChannel.whatsapp:
        return 'WhatsApp';
      case OtpChannel.push:
        return 'Forge notifications';
      case OtpChannel.sms:
      case OtpChannel.auto:
        return 'SMS';
    }
  }

  /// Destination used in the screen subtitle ("We sent a 6-digit code
  /// to `[destination]`"). Prefers the server's [channelHint] when
  /// present; otherwise derives from channel + phone so the copy is
  /// always concrete, never the generic "your phone".
  String _destinationLabel() {
    final hint = _channelHint;
    if (hint != null && hint.isNotEmpty) return hint;
    switch (_channel) {
      case OtpChannel.whatsapp:
        return 'your WhatsApp (${_formattedPhone()})';
      case OtpChannel.push:
        return 'your Forge app';
      case OtpChannel.sms:
      case OtpChannel.auto:
        return _formattedPhone();
    }
  }

  String _countdownLabel() {
    final mm = _remaining.inMinutes.remainder(60).toString();
    final ss = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const BackButtonHeader(),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Enter the code',
                style: AppTextStyles.headlineLarge.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text.rich(
                TextSpan(
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                  children: <InlineSpan>[
                    const TextSpan(text: 'We sent a 6-digit code to '),
                    TextSpan(
                      text: _destinationLabel(),
                      style: TextStyle(
                        color: palette.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _ChannelBadge(channel: _channel),
              const SizedBox(height: AppSpacing.xl),
              OtpInput(
                controller: _otpController,
                onChanged: (String v) {
                  setState(() {
                    _value = v;
                    if (_errorText != null) _errorText = null;
                  });
                },
                onCompleted: (String _) => _verify(),
                errorText: _errorText,
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: AppTextButton(
                  label: 'Paste OTP from clipboard',
                  icon: const Icon(Icons.content_paste_rounded, size: 16),
                  onPressed: () => _tryPasteFromClipboard(),
                  dense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: _remaining > Duration.zero
                    ? Text(
                        'Resend code in ${_countdownLabel()}',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: palette.onSurfaceVariant,
                        ),
                      )
                    : AppTextButton(
                        label: 'Resend code',
                        onPressed: _resend,
                      ),
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Verify',
                isLoading: _submitting,
                onPressed: _value.length == 6 ? _verify : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact pill under the subtitle that names the channel the OTP was
/// delivered through. Helps the worker know whether to check WhatsApp,
/// their SMS inbox, or the Forge notification tray.
class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.channel});
  final OtpChannel channel;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final IconData icon;
    final String label;
    final Color tint;
    switch (channel) {
      case OtpChannel.whatsapp:
        icon = Icons.chat_rounded;
        label = 'Sent via WhatsApp';
        tint = const Color(0xFF25D366);
        break;
      case OtpChannel.push:
        icon = Icons.notifications_active_rounded;
        label = 'Sent to your Forge app';
        tint = palette.primary;
        break;
      case OtpChannel.sms:
      case OtpChannel.auto:
        icon = Icons.sms_rounded;
        label = 'Sent via SMS';
        tint = palette.onSurfaceVariant;
        break;
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tint.withValues(alpha: 0.30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: tint,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
