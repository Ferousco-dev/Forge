import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_radius.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/mock/mock_providers.dart';
import '../../../core/mock/models.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_text_button.dart';
import '../../../shared/widgets/back_button_header.dart';
import '../../../shared/widgets/currency_text.dart';
import '../../../shared/widgets/empty_state_view.dart';

/// Loan detail — outstanding balance, repayment progress, payment
/// schedule (past + upcoming), full term disclosure, support link.
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.loanId});
  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final loanAsync = ref.watch(activeLoanProvider);

    return Scaffold(
      backgroundColor: palette.surface,
      body: loanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace _) => SafeArea(
          child: Column(
            children: <Widget>[
              const BackButtonHeader(),
              const Expanded(
                child: EmptyStateView(
                  title: "Couldn't load this loan",
                  subtitle: 'Try again — your record is safe.',
                ),
              ),
            ],
          ),
        ),
        data: (Loan? loan) {
          if (loan == null || loan.id != loanId) {
            return SafeArea(
              child: Column(
                children: <Widget>[
                  const BackButtonHeader(),
                  const Expanded(
                    child: EmptyStateView(
                      title: 'No matching loan',
                      subtitle: 'This loan record is no longer available.',
                    ),
                  ),
                ],
              ),
            );
          }
          return _Body(loan: loan);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.loan});
  final Loan loan;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final perJob = (loan.principal * loan.repaymentPercentPerJob).round();
    final totalRepayable = (loan.principal * 1.08).round();
    final completedJobs = loan.repayments.length;
    final remaining = (loan.outstandingBalance / perJob).ceil();

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          0,
          0,
          0,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Top bar.
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  const BackButtonHeader(),
                  Expanded(
                    child: Text(
                      'Loan details',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleLarge.copyWith(
                        color: palette.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _SummaryCard(
                    loan: loan,
                    perJobAmount: perJob,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Payment schedule',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: <Widget>[
                        // Past payments (with checkmarks).
                        for (int i = 0; i < loan.repayments.length; i++)
                          _PaymentRow(
                            paid: true,
                            label: 'Payment ${i + 1}',
                            subtitle: _formatDate(
                                loan.repayments[i].paidAt),
                            amount: loan.repayments[i].amount,
                          ),
                        // Upcoming payments.
                        for (int i = 0; i < remaining.clamp(0, 4); i++)
                          _PaymentRow(
                            paid: false,
                            label:
                                'Payment ${completedJobs + i + 1}',
                            subtitle: 'Auto-deducts from your '
                                'next eligible job',
                            amount: i == remaining - 1 &&
                                    loan.outstandingBalance % perJob != 0
                                ? loan.outstandingBalance % perJob
                                : perJob,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Loan terms',
                    style: AppTextStyles.titleLarge.copyWith(
                      color: palette.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      children: <Widget>[
                        _TermRow(
                          label: 'Principal',
                          value: '₦${loan.principal}',
                        ),
                        Divider(
                          height: AppSpacing.lg,
                          color: palette.outlineVariant,
                        ),
                        _TermRow(
                          label: 'Interest',
                          value:
                              '${loan.interestRatePercent.toStringAsFixed(0)}%',
                        ),
                        Divider(
                          height: AppSpacing.lg,
                          color: palette.outlineVariant,
                        ),
                        _TermRow(
                          label: 'Per-job repayment',
                          value: '₦$perJob',
                        ),
                        Divider(
                          height: AppSpacing.lg,
                          color: palette.outlineVariant,
                        ),
                        _TermRow(
                          label: 'Disbursed',
                          value: _formatDate(loan.disbursedAt),
                        ),
                        Divider(
                          height: AppSpacing.lg,
                          color: palette.outlineVariant,
                        ),
                        _TermRow(
                          label: 'Total repayable',
                          value: '₦$totalRepayable',
                          emphasized: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Center(
                    child: AppTextButton(
                      label: 'Need help with this loan?',
                      icon: const Icon(Icons.support_agent_rounded),
                      onPressed: () {},
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.loan, required this.perJobAmount});

  final Loan loan;
  final int perJobAmount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      borderColor: palette.primary.withValues(alpha: 0.18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'OUTSTANDING',
            style: AppTextStyles.labelSmall.copyWith(
              color: palette.primary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          CurrencyText(
            amount: loan.outstandingBalance,
            size: CurrencySize.large,
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.full),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: loan.progressFraction,
              valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
              backgroundColor: palette.outlineVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(
                  '${(loan.progressFraction * 100).round()}% repaid',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  'Original ₦${loan.principal}',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.paid,
    required this.label,
    required this.subtitle,
    required this.amount,
  });

  final bool paid;
  final String label;
  final String subtitle;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: paid
                  ? palette.success.withValues(alpha: 0.10)
                  : palette.surfaceContainerHigh,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: paid
                ? Icon(Icons.check_rounded,
                    size: 16, color: palette.success)
                : Icon(Icons.schedule_rounded,
                    size: 16, color: palette.onSurfaceVariant),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: palette.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '₦$amount',
            style: AppTextStyles.bodyMedium.copyWith(
              color: paid ? palette.onSurface : palette.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TermRow extends StatelessWidget {
  const _TermRow({
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

String _formatDate(DateTime when) {
  return DateFormat('MMM d, yyyy').format(when.toLocal());
}
