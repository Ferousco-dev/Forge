import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/route_paths.dart';
import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confetti_overlay.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../../shared/widgets/secondary_button.dart';

/// Loan approved — confetti + green check + amount + repayment summary.
///
/// Reads the active loan from [activeLoanProvider] so the numbers
/// shown here match what the previous screens (eligibility +
/// application) just displayed. The provider is `keepAlive` so a
/// page transition from the application screen to here doesn't fire
/// a second fetch.
class LoanApprovedScreen extends ConsumerWidget {
  const LoanApprovedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final loanAsync = ref.watch(activeLoanProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: palette.surface,
        body: Stack(
          children: <Widget>[
            SafeArea(
              child: loanAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (Object _, StackTrace _) => const EmptyStateView(
                  title: 'Loan record unavailable',
                ),
                data: (Loan? loan) {
                  final amount = loan?.principal ?? 50000;
                  final perJob = loan == null
                      ? (amount * 0.15).round()
                      : (loan.principal * loan.repaymentPercentPerJob).round();
                  final total = loan == null
                      ? (amount * 1.08).round()
                      : (loan.principal * 1.08).round();

                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xl,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _SuccessHero(),
                        const SizedBox(height: AppSpacing.xl),
                        _AmountCard(amount: amount),
                        const SizedBox(height: AppSpacing.lg),
                        _RepaymentSummary(
                          perJobAmount: perJob,
                          totalRepayable: total,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        if (loan != null)
                          PrimaryButton(
                            label: 'View loan details',
                            onPressed: () => context.go(
                              RoutePaths.loanDetail(loan.id),
                            ),
                          ),
                        if (loan != null) const SizedBox(height: AppSpacing.sm),
                        SecondaryButton(
                          label: 'Done',
                          onPressed: () => context.go(RoutePaths.loans),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const Positioned.fill(child: ConfettiOverlay()),
          ],
        ),
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Column(
      children: <Widget>[
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: palette.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_circle_rounded,
            size: 64,
            color: palette.success,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Loan approved!',
          textAlign: TextAlign.center,
          style: AppTextStyles.headlineLarge.copyWith(
            color: palette.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'A bank partner approved your application.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium.copyWith(
            color: palette.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _AmountCard extends StatelessWidget {
  const _AmountCard({required this.amount});
  final int amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.success.withValues(alpha: 0.30),
      background: palette.success.withValues(alpha: 0.06),
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                Icons.account_balance_wallet_rounded,
                size: 16,
                color: palette.success,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Sent to your wallet',
                style: AppTextStyles.labelMedium.copyWith(
                  color: palette.success,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          CurrencyText(
            amount: amount,
            size: CurrencySize.large,
            tone: CurrencyTone.credit,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Disbursed instantly via Squad',
            style: AppTextStyles.bodySmall.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RepaymentSummary extends StatelessWidget {
  const _RepaymentSummary({
    required this.perJobAmount,
    required this.totalRepayable,
  });

  final int perJobAmount;
  final int totalRepayable;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      borderRadius: AppRadius.allLg,
      child: Column(
        children: <Widget>[
          _SummaryRow(
            label: 'Repayment per job',
            value: '₦$perJobAmount',
          ),
          Divider(height: AppSpacing.lg, color: palette.outlineVariant),
          _SummaryRow(
            label: 'Total repayable',
            value: '₦$totalRepayable',
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.bodyMedium.copyWith(
              color: palette.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(
              color: emphasized ? palette.primary : palette.onSurface,
              fontWeight: emphasized ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
