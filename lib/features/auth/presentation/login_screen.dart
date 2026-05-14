import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../data/auth_models.dart';
import '../state/auth_state.dart';
import '_phone_entry_scaffold.dart';
import 'otp_screen.dart';

/// Phone-number entry for **returning** users.
///
/// Layout: time-based greeting kicker, "Welcome back" title, helper
/// line, phone input with locked `+234` prefix, "Continue" CTA, and a
/// "New here? Create an account" footer link.
///
/// No back arrow — login is the entry point of the auth flow.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning 👋';
    if (h < 17) return 'Good afternoon 👋';
    return 'Good evening 👋';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PhoneEntryScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to keep building your record.',
      greeting: _greeting(),
      showBack: false,
      ctaLabel: 'Continue',
      footerPrompt: 'New here? ',
      footerActionLabel: 'Create an account',
      onContinue: (String phone) async {
        final challenge = await ref
            .read(authRepositoryProvider)
            .requestOtp(localPhone: phone, flow: OtpFlow.login);
        if (!context.mounted) return;
        context.push(
          RoutePaths.otp,
          extra: OtpFlowExtra(
            phone: phone,
            flow: OtpFlow.login,
            challengeId: challenge.challengeId,
            expiresAt: challenge.expiresAt,
            resendAfterSeconds: challenge.resendAfterSeconds,
            channel: challenge.channel,
            channelHint: challenge.channelHint,
          ),
        );
      },
      onFooterAction: () => context.go(RoutePaths.signup),
    );
  }
}
