import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/secondary_button.dart';

/// Loan application "under review" screen.
///
/// In production a notification would arrive when the bank partner
/// responds. For the static-UI demo we simulate an outcome by giving
/// the user two affordances at the bottom: "Simulate approval" and
/// "Simulate rejection" — both routed via `pushReplacement` so the
/// pending screen isn't reachable via back-navigation from outcomes.
class LoanPendingScreen extends StatefulWidget {
  const LoanPendingScreen({super.key});

  @override
  State<LoanPendingScreen> createState() => _LoanPendingScreenState();
}

class _LoanPendingScreenState extends State<LoanPendingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Spacer(flex: 2),
              Center(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (BuildContext context, _) => Transform.rotate(
                    angle: _controller.value * 2 * math.pi,
                    child: _Hourglass(palette: palette),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Application under review',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineMedium.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                ),
                child: Text(
                  'A bank partner is reviewing your application. '
                  "We'll notify you within 24 hours.",
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppCard(
                padding: const EdgeInsets.all(AppSpacing.md),
                background: palette.surfaceContainerHigh,
                child: Row(
                  children: <Widget>[
                    Icon(Icons.schedule_rounded,
                        size: 18, color: palette.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        "You'll be free to apply for another loan once "
                        'this one is decided.',
                        style: AppTextStyles.bodySmall.copyWith(
                          color: palette.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 3),

              SecondaryButton(
                label: 'Back to home',
                onPressed: () => context.go(RoutePaths.loans),
              ),
              const SizedBox(height: AppSpacing.md),

              // Demo affordances — not production UI. Lets us show both
              // approval and rejection during a live walkthrough.
              Wrap(
                alignment: WrapAlignment.center,
                spacing: AppSpacing.md,
                children: <Widget>[
                  AppTextButton(
                    label: 'Simulate approval',
                    icon: const Icon(Icons.bug_report_outlined),
                    onPressed: () =>
                        context.pushReplacement(RoutePaths.loanApproved),
                    dense: true,
                  ),
                  AppTextButton(
                    label: 'Simulate rejection',
                    icon: const Icon(Icons.bug_report_outlined),
                    onPressed: () =>
                        context.pushReplacement(RoutePaths.loanRejected),
                    color: palette.onSurfaceVariant,
                    dense: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hourglass extends StatelessWidget {
  const _Hourglass({required this.palette});
  final dynamic palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: palette.primaryContainer as Color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.hourglass_top_rounded,
        size: 56,
        color: palette.primary as Color,
      ),
    );
  }
}
