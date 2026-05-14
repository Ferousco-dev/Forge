import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../data/auth_models.dart';
import '../state/auth_state.dart';
import '_phone_entry_scaffold.dart';
import 'otp_screen.dart';

/// Phone-number entry for **new** users.
///
/// Mirror of [LoginScreen] with copy and navigation flipped: heading
/// reads "Create your account", footer link offers a path back to login,
/// and a successful OTP routes to profile setup rather than home.
class SignupScreen extends ConsumerWidget {
  const SignupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PhoneEntryScaffold(
      title: 'Create your account',
      subtitle: 'Start earning. Build a record the financial system can see.',
      ctaLabel: 'Continue',
      footerPrompt: 'Already have an account? ',
      footerActionLabel: 'Sign in',
      onContinue: (String phone) async {
        final challenge = await ref
            .read(authRepositoryProvider)
            .requestOtp(localPhone: phone, flow: OtpFlow.signup);
        if (!context.mounted) return;
        context.push(
          RoutePaths.otp,
          extra: OtpFlowExtra(
            phone: phone,
            flow: OtpFlow.signup,
            challengeId: challenge.challengeId,
            expiresAt: challenge.expiresAt,
            resendAfterSeconds: challenge.resendAfterSeconds,
            channel: challenge.channel,
            channelHint: challenge.channelHint,
          ),
        );
      },
      onFooterAction: () => context.go(RoutePaths.login),
    );
  }
}
