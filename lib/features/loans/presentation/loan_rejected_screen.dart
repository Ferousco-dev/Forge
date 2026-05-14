import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/secondary_button.dart';

/// Loan rejected — friendly tone, encouraging tips.
///
/// Brief calls for "not a sad face — too aggressive". The illustration
/// is a soft cluster of dots (like a constellation) inside a tinted
/// circle: neutral, calm, doesn't read as failure.
class LoanRejectedScreen extends StatelessWidget {
  const LoanRejectedScreen({super.key});

  static const List<({String title, String body})> _tips = [
    (
      title: 'Keep working consistently',
      body: 'Your reliability score grows each time you complete '
          'a job on time.',
    ),
    (
      title: 'Build a longer record',
      body: 'Lenders look at how long and how steadily you\'ve '
          'been earning through Forge.',
    ),
    (
      title: 'Try again in 30 days',
      body: 'Your eligibility is recalculated regularly. Most '
          'workers qualify after a few more weeks of work.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Center(child: _FriendlyIllustration()),
              const SizedBox(height: AppSpacing.xl),
              Text(
                "We couldn't approve this loan right now",
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineSmall.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Text(
                  "Don't worry. Keep working through Forge and your "
                  'credit score will grow. Most workers qualify after '
                  'a few more weeks.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Ways to improve your score',
                style: AppTextStyles.titleLarge.copyWith(
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              for (int i = 0; i < _tips.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: AppSpacing.sm),
                _TipCard(index: i + 1, tip: _tips[i]),
              ],
              const SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: 'Back to home',
                onPressed: () => context.go(RoutePaths.loans),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FriendlyIllustration extends StatelessWidget {
  const _FriendlyIllustration();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        color: palette.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.trending_up_rounded,
        size: 64,
        color: palette.primary,
      ),
    );
  }
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.index, required this.tip});
  final int index;
  final ({String title, String body}) tip;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      borderRadius: AppRadius.allLg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: palette.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: AppTextStyles.titleSmall.copyWith(
                color: palette.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  tip.title,
                  style: AppTextStyles.titleSmall.copyWith(
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tip.body,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
